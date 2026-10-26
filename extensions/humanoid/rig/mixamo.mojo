# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Mixamo animations on a game humanoid's nineteen bones.

A Mixamo download is an FBX file of one character's skeleton and one
animation. The skeleton has sixty-five bones in a T-pose. The humanoid has
nineteen and stands with its arms by its sides. `retarget_mixamo` turns the
animation into an `AnimationClip` of the humanoid's own bones, so the clip
plays in an `AnimationMixer` as `walk_clip` does.

**How a bone is carried over.** Each humanoid bone has one Mixamo bone that
drives it:

| Humanoid | Mixamo |
|---|---|
| hips | Hips |
| spine, chest | Spine1, Spine2 |
| neck, head | Neck, Head |
| upper arm, forearm, hand | Arm, ForeArm, Hand |
| thigh, shin, foot, toes | UpLeg, Leg, Foot, ToeBase |

The shoulders, the lowest spine bone and the fingers have no humanoid bone.
The world turn of a driver already holds the turn of every bone above it,
so nothing is lost.

For each sample the retarget takes the driver's world turn since the rest
pose, and carries it to the humanoid's bone. The humanoid's bone is first
swung from where it hangs at rest to where the driver stands at rest. The
driver's turn is then applied to it. So the humanoid's bone points where the
driver points in every frame, whatever the two rest poses are. The bone's
twist follows the driver's twist since the rest pose.

**Which side is which.** Mixamo faces +z and its left side stands at +x. The
humanoid faces +z and its right side stands at +x. So the retarget pairs the
sides by where they stand and not by their names: a Mixamo left arm drives
the humanoid arm at +x. A rig that stands the other way pairs the other way.

**The hips.** The hips move as the Mixamo hips move from the rest pose,
scaled by the ratio of the two skeletons' hip heights above the ankles. With
`in_place` the straight line from the first frame to the last is taken out
of the hips' travel along the ground, so a walk stays near the origin and
keeps its sway. A game moves the humanoid's root node itself.

**What the file must hold.** The file's own pose is the rest pose. Mixamo
files hold their T-pose there. The file must hold the Hips, and an Arm, a
ForeArm, an UpLeg, a Leg and a Foot of each side. Bones of the spine, the
head, the hands and the toes are optional. A joint whose bone is missing
turns as its parent does.

This is not a three.js port. See Extensions.

    var clips = read_mixamo("Walking.fbx", person.bones, person.rig)
    var walk = mixer.add(AnimationAction(clips[0].copy()))
"""

from animation.animation_clip import AnimationClip
from animation.keyframe_track import POSITION, QUATERNION, SCALE, KeyframeTrack
from core.assets import Assets
from core.object3d import NO_PARENT, NodeId
from core.scene import Scene
from extensions.humanoid.rig.clips import SAMPLES_PER_SECOND
from extensions.humanoid.rig.joints import (
    CHEST,
    HEAD,
    HIPS,
    JOINT_COUNT,
    LEFT_FOOT,
    LEFT_FOREARM,
    LEFT_SHIN,
    LEFT_THIGH,
    LEFT_TOES,
    LEFT_UPPER_ARM,
    NECK,
    RIGHT_FOOT,
    RIGHT_FOREARM,
    RIGHT_SHIN,
    RIGHT_THIGH,
    RIGHT_TOES,
    RIGHT_UPPER_ARM,
    SPINE,
    HumanoidRig,
    Joint,
    joint_parent,
)
from loaders.fbx import FbxModel, read_fbx
from math.quaternion import Quaternion, append_quaternion
from math.vector3 import Vector3, append_vector3
from units.si import SECOND, Duration

# The Mixamo bones a retarget reads, as the numbers `mixamo_role` returns.
# The first seven are the trunk and the head. Then come the left side's
# eight and the right side's eight, each: arm, forearm, hand, up leg, leg,
# foot, toe base and toe end.
comptime ROLE_HIPS = 0
"""The role of `Hips`."""
comptime ROLE_SPINE1 = 2
"""The role of `Spine1`."""
comptime ROLE_SPINE2 = 3
"""The role of `Spine2`."""
comptime ROLE_NECK = 4
"""The role of `Neck`."""
comptime ROLE_HEAD = 5
"""The role of `Head`."""
comptime ROLE_HEAD_TOP = 6
"""The role of `HeadTop_End`."""
comptime ROLE_SIDE_START = 7
"""The role of the left arm, the first bone of a side."""
comptime ROLE_PER_SIDE = 8
"""How many roles each side has."""
comptime ROLE_COUNT = 23
"""How many roles there are."""
comptime _ARM = 0
comptime _FOREARM = 1
comptime _UP_LEG = 3
comptime _LEG = 4
comptime _FOOT = 5

# How far a sample may fall short of the clip's end before the end gets a
# key of its own, in seconds.
comptime _END_TOLERANCE = Float32(1e-4)


struct MixamoOptions(Copyable, Movable):
    """What a retarget does besides the turns of the bones."""

    var in_place: Bool
    """True to take the straight-line travel along the ground out of the
    hips. False keeps all of it."""
    var samples_per_second: Int
    """How many keys a second the new clip holds."""

    def __init__(
        out self,
        in_place: Bool = True,
        samples_per_second: Int = SAMPLES_PER_SECOND,
    ):
        """Hold the options.

        Args:
            in_place: Whether the hips stay near the origin.
            samples_per_second: Keys a second, above zero.
        """
        self.in_place = in_place
        self.samples_per_second = samples_per_second


def _role_keys() -> List[String]:
    """Return the key of each role, in the order of the roles."""
    var keys: List[String] = [
        "hips",
        "spine",
        "spine1",
        "spine2",
        "neck",
        "head",
        "headtopend",
        "leftarm",
        "leftforearm",
        "lefthand",
        "leftupleg",
        "leftleg",
        "leftfoot",
        "lefttoebase",
        "lefttoeend",
        "rightarm",
        "rightforearm",
        "righthand",
        "rightupleg",
        "rightleg",
        "rightfoot",
        "righttoebase",
        "righttoeend",
    ]
    return keys^


def mixamo_key(name: String) -> String:
    """Return a bone's name without its prefix, in lower case.

    Mixamo writes `mixamorig:Hips`. A file that went through other tools
    can hold `mixamorig1:Hips`, `mixamorigHips` or just `Hips`. The key
    keeps letters and digits only.

    Args:
        name: The bone's name.

    Returns:
        The name in lower case, without punctuation and without the
        `mixamorig` prefix and the number that can follow it.
    """
    var kept = List[UInt8]()
    for byte in name.as_bytes():
        var letter = byte
        if letter >= 65 and letter <= 90:
            letter += 32
        if (letter >= 97 and letter <= 122) or (letter >= 48 and letter <= 57):
            kept.append(letter)
    var key = String(unsafe_from_utf8=kept)
    var prefix = key.find("mixamorig")
    if prefix < 0:
        return key^
    var start = prefix + 9
    var bytes = key.as_bytes()
    # The key holds digits and lower case letters, and the digits sort first.
    while start < len(bytes) and bytes[start] <= 57:
        start += 1
    return String(key[byte=start:])


def mixamo_role(name: String) -> Int:
    """Return which bone of the Mixamo skeleton a name is.

    Args:
        name: A bone's name, as `mixamo_key` reads it.

    Returns:
        A number from zero to `ROLE_COUNT` minus one, or minus one when the
        retarget reads no bone of that name.
    """
    var key = mixamo_key(name)
    var keys = _role_keys()
    for role in range(ROLE_COUNT):  # pragma: no branch
        if keys[role] == key:
            return role
    return -1


def _side_role(side: Int, bone: Int) -> Int:
    """Return the role of one bone of one side: side zero is the left."""
    return ROLE_SIDE_START + ROLE_PER_SIDE * side + bone


def _driver_roles(crossed: Bool) -> List[Int]:
    """Return the Mixamo role that drives each joint.

    Args:
        crossed: True when a Mixamo left bone drives the humanoid's right
            joint.

    Returns:
        One role per joint, in the order of the joints.
    """
    var roles = List[Int](length=JOINT_COUNT, fill=-1)
    roles[HIPS.value] = ROLE_HIPS
    roles[SPINE.value] = ROLE_SPINE1
    roles[CHEST.value] = ROLE_SPINE2
    roles[NECK.value] = ROLE_NECK
    roles[HEAD.value] = ROLE_HEAD
    for side in range(2):  # pragma: no branch
        var left = (side == 0) != crossed
        var arm = LEFT_UPPER_ARM.value if left else RIGHT_UPPER_ARM.value
        var leg = LEFT_THIGH.value if left else RIGHT_THIGH.value
        for k in range(3):  # pragma: no branch
            roles[arm + k] = _side_role(side, _ARM + k)
        for k in range(4):  # pragma: no branch
            roles[leg + k] = _side_role(side, _UP_LEG + k)
    return roles^


def _aim_roles(drivers: List[Int]) -> List[Int]:
    """Return the Mixamo role each joint's bone points at, or minus one.

    A joint points at the bone that drives the joint below it. The head
    points at the top of the head and the toes at the end of the toes. The
    hands point at nothing: the finger bones do not tell where the wrist
    points.

    Args:
        drivers: The role that drives each joint.

    Returns:
        One role per joint, or minus one for a joint with no aim.
    """
    var aims = List[Int](length=JOINT_COUNT, fill=-1)
    var chained: List[Joint] = [
        HIPS,
        SPINE,
        CHEST,
        NECK,
        RIGHT_UPPER_ARM,
        RIGHT_FOREARM,
        LEFT_UPPER_ARM,
        LEFT_FOREARM,
        RIGHT_THIGH,
        RIGHT_SHIN,
        RIGHT_FOOT,
        LEFT_THIGH,
        LEFT_SHIN,
        LEFT_FOOT,
    ]
    for joint in chained:  # pragma: no branch
        aims[joint.value] = drivers[joint.value + 1]
    aims[HEAD.value] = ROLE_HEAD_TOP
    # The toe end follows the toe base in the roles.
    aims[RIGHT_TOES.value] = drivers[RIGHT_TOES.value] + 1
    aims[LEFT_TOES.value] = drivers[LEFT_TOES.value] + 1
    return aims^


struct _Plan(Movable):
    """What a retarget works out from the rest pose, once per file."""

    var driver: List[NodeId]
    """Each joint's Mixamo bone, or `NO_PARENT` when the file lacks it."""
    var swing: List[Quaternion]
    """Each joint's turn from where its bone hangs to where its driver
    stands at rest."""
    var rest_inverse: List[Quaternion]
    """The inverse of each driver's world turn at rest."""
    var hips_rest: Vector3
    """Where the Mixamo hips stand at rest, in world space."""
    var ratio: Float32
    """The humanoid's hip height over the Mixamo skeleton's."""

    def __init__(out self):
        """Start with no joints driven."""
        self.driver = List[NodeId](length=JOINT_COUNT, fill=NO_PARENT)
        self.swing = List[Quaternion](
            length=JOINT_COUNT, fill=Quaternion.identity()
        )
        self.rest_inverse = List[Quaternion](
            length=JOINT_COUNT, fill=Quaternion.identity()
        )
        self.hips_rest = Vector3(0, 0, 0)
        self.ratio = 1


@fieldwise_init
struct _Transform(Copyable, Movable):
    """One node's local transform, kept to put the node back."""

    var position: Vector3
    var quaternion: Quaternion
    var scale: Vector3


def _world_rotation(scene: Scene, node: NodeId) raises -> Quaternion:
    """Return the turn of a node's world matrix."""
    var position = Vector3(0, 0, 0)
    var rotation = Quaternion.identity()
    var scale = Vector3(1, 1, 1)
    scene.world_matrix(node).decompose(position, rotation, scale)
    rotation.normalize()
    return rotation


def _find_roles(source: FbxModel) -> List[NodeId]:
    """Return the node of each Mixamo role, or `NO_PARENT`."""
    var found = List[NodeId](length=ROLE_COUNT, fill=NO_PARENT)
    for index in range(len(source.models)):  # pragma: no branch
        var role = mixamo_role(source.model_names[index])
        if role >= 0 and found[role] == NO_PARENT:
            found[role] = source.models[index]
    return found^


def _require_roles(found: List[NodeId]) raises:
    """Refuse a skeleton that lacks a bone the retarget cannot do without.

    Raises:
        Error: Naming the first missing bone.
    """
    var keys = _role_keys()
    var needed: List[Int] = [ROLE_HIPS]
    for side in range(2):  # pragma: no branch
        for bone in [_ARM, _FOREARM, _UP_LEG, _LEG, _FOOT]:  # pragma: no branch
            needed.append(_side_role(side, bone))
    for role in needed:  # pragma: no branch
        if found[role] == NO_PARENT:
            raise Error("Mixamo: the file has no bone named " + keys[role])


def _axis(rig: HumanoidRig, joint: Int) -> Vector3:
    """Return the direction a humanoid bone points at rest, of length one."""
    var axis = rig.ends[joint] - rig.joints[joint]
    axis.normalize()
    return axis


def _plan(scene: Scene, source: FbxModel, rig: HumanoidRig) raises -> _Plan:
    """Work out the swings, the rest turns and the hip scale.

    The scene must be at the rest pose and updated.

    Raises:
        Error: If a needed bone is missing or the skeleton has no height.
    """
    var found = _find_roles(source)
    _require_roles(found)
    var left_x = scene.world_position(found[_side_role(0, _ARM)]).x
    var right_x = scene.world_position(found[_side_role(1, _ARM)]).x
    var crossed = (left_x > right_x) != (
        rig.joints[LEFT_UPPER_ARM.value].x > rig.joints[RIGHT_UPPER_ARM.value].x
    )
    var drivers = _driver_roles(crossed)
    var aims = _aim_roles(drivers)
    var plan = _Plan()
    for j in range(JOINT_COUNT):  # pragma: no branch
        var node = found[drivers[j]]
        plan.driver[j] = node
        if node == NO_PARENT:
            continue
        plan.rest_inverse[j] = _world_rotation(scene, node).conjugate()
        var aim = found[aims[j]] if aims[j] >= 0 else NO_PARENT
        if aim != NO_PARENT:
            var seen = scene.world_position(aim) - scene.world_position(node)
            seen.normalize()
            plan.swing[j] = Quaternion.from_unit_vectors(_axis(rig, j), seen)
        elif j != HIPS.value:
            plan.swing[j] = plan.swing[joint_parent(Joint(j)).value]
    var hips = scene.world_position(found[ROLE_HIPS])
    plan.hips_rest = hips
    var ankles = (
        scene.world_position(found[_side_role(0, _FOOT)]).y
        + scene.world_position(found[_side_role(1, _FOOT)]).y
    ) / 2
    var height = hips.y - ankles
    if not (height > 0):
        raise Error("Mixamo: the hips must stand above the feet")
    var own = (
        rig.joints[HIPS.value].y
        - (rig.joints[LEFT_FOOT.value].y + rig.joints[RIGHT_FOOT.value].y) / 2
    )
    plan.ratio = own / height
    return plan^


def _save(scene: Scene, source: FbxModel) raises -> List[_Transform]:
    """Return every model's local transform."""
    var saved = List[_Transform]()
    for node in source.models:  # pragma: no branch
        var held = scene.get(node)
        saved.append(_Transform(held.position, held.quaternion, held.scale))
    return saved^


def _restore(
    mut scene: Scene, source: FbxModel, saved: List[_Transform]
) raises:
    """Put every model back where `_save` found it."""
    for index in range(len(source.models)):  # pragma: no branch
        ref held = scene.node(source.models[index])
        held.position = saved[index].position
        held.quaternion = saved[index].quaternion
        held.scale = saved[index].scale
    scene.update()


def _pose(mut scene: Scene, clip: AnimationClip, at: Duration) raises:
    """Set every node a track drives to the track's value at a time."""
    for track in clip.tracks:  # pragma: no branch
        var kind = track.target.kind
        if kind == POSITION:
            scene.node(
                NodeId(track.target.index)
            ).position = track.sample_vector3(at)
        elif kind == SCALE:
            scene.node(NodeId(track.target.index)).scale = track.sample_vector3(
                at
            )
        elif kind == QUATERNION:
            scene.node(
                NodeId(track.target.index)
            ).quaternion = track.sample_quaternion(at)
    scene.update()


def _sample_times(seconds: Float32, per_second: Int) -> List[Float32]:
    """Return when to sample a clip: every step, and the end."""
    var rate = Float32(per_second)
    var count = Int(seconds * rate)
    var at = List[Float32](capacity=count + 2)
    for k in range(count + 1):  # pragma: no branch
        at.append(Float32(k) / rate)
    if seconds - at[count] > _END_TOLERANCE:
        at.append(seconds)
    return at^


def _take_out_travel(mut travel: List[Vector3], at: List[Float32]):
    """Take the straight line from the first frame to the last out of the
    travel along x and z, and start both at zero. A clip of no length only
    starts at zero."""
    var first = travel[0]
    var last = travel[len(travel) - 1]
    var span = at[len(at) - 1]
    for k in range(len(travel)):  # pragma: no branch
        # A clip of no length, a still pose, has one frame and no line.
        var along = at[k] / span if span > 0 else Float32(0)
        travel[k].x -= first.x + (last.x - first.x) * along
        travel[k].z -= first.z + (last.z - first.z) * along


def _retarget_clip(
    mut scene: Scene,
    clip: AnimationClip,
    plan: _Plan,
    bones: List[NodeId],
    rig: HumanoidRig,
    options: MixamoOptions,
) raises -> AnimationClip:
    """Sample one clip of the Mixamo skeleton into a clip of the humanoid."""
    var at = _sample_times(clip.length, options.samples_per_second)
    var times = List[Duration](capacity=len(at))
    var turns = List[List[Float32]]()
    for _ in range(JOINT_COUNT):  # pragma: no branch
        turns.append(List[Float32](capacity=4 * len(at)))
    var kept = List[Quaternion](length=JOINT_COUNT, fill=Quaternion.identity())
    var travel = List[Vector3](capacity=len(at))
    for k in range(len(at)):  # pragma: no branch
        times.append(Duration(at[k], SECOND))
        _pose(scene, clip, times[k])
        var world = List[Quaternion](
            length=JOINT_COUNT, fill=Quaternion.identity()
        )
        for j in range(JOINT_COUNT):  # pragma: no branch
            var above = Quaternion.identity()
            if j != HIPS.value:
                above = world[joint_parent(Joint(j)).value]
            if plan.driver[j] == NO_PARENT:
                world[j] = above
            else:
                var since = _world_rotation(scene, plan.driver[j])
                world[j] = (since * plan.rest_inverse[j]) * plan.swing[j]
            var local = above.conjugate() * world[j]
            local.normalize()
            # The same rotation has two quaternions. Keep the near one, so
            # a blend between two keys turns the short way.
            if k > 0 and local.dot(kept[j]) < 0:
                local = local * Float32(-1)
            kept[j] = local
            append_quaternion(turns[j], local)
        travel.append(
            (scene.world_position(plan.driver[HIPS.value]) - plan.hips_rest)
            * plan.ratio
        )
    if options.in_place:
        _take_out_travel(travel, at)
    var tracks = List[KeyframeTrack]()
    for j in range(JOINT_COUNT):  # pragma: no branch
        tracks.append(
            KeyframeTrack(bones[j], QUATERNION, times, turns[j].copy())
        )
    var rest = rig.local(HIPS)
    var places = List[Float32](capacity=3 * len(at))
    for k in range(len(at)):  # pragma: no branch
        append_vector3(places, rest + travel[k])
    tracks.append(KeyframeTrack(bones[HIPS.value], POSITION, times, places^))
    return AnimationClip(clip.name, tracks^)


def retarget_mixamo(
    mut scene: Scene,
    source: FbxModel,
    bones: List[NodeId],
    rig: HumanoidRig,
    options: MixamoOptions = MixamoOptions(),
) raises -> List[AnimationClip]:
    """Return the humanoid's clips for each animation in a Mixamo file.

    The scene is a scratch scene that holds the file. The retarget poses
    its nodes to sample the clips, and puts them back at the end.

    Args:
        scene: The scene `read_fbx` filled with the file.
        source: What `read_fbx` returned for it.
        bones: One node per joint of the humanoid, in the order of the
            joints. The clips drive these.
        rig: The rig the bones were placed from.
        options: Whether the hips stay in place, and the sampling rate.

    Returns:
        One clip per animation stack of the file, each of a quaternion
        track per joint and a position track for the hips.

    Raises:
        Error: If there is not one bone per joint; the rate is below one;
            the file holds no animation or lacks a bone that `read_mixamo`
            lists; or the hips do not stand above the feet.
    """
    if len(bones) != JOINT_COUNT:
        raise Error("A humanoid clip needs one bone per joint")
    if options.samples_per_second < 1:
        raise Error("A retarget needs a sampling rate of one or more")
    if len(source.animations) == 0:
        raise Error("Mixamo: the file holds no animation")
    var saved = _save(scene, source)
    scene.update()
    var plan = _plan(scene, source, rig)
    var clips = List[AnimationClip]()
    for index in range(len(source.animations)):  # pragma: no branch
        _restore(scene, source, saved)
        clips.append(
            _retarget_clip(
                scene, source.animations[index], plan, bones, rig, options
            )
        )
    _restore(scene, source, saved)
    return clips^


def _clip_name(path: String, stack: String, count: Int) -> String:
    """Return a clip's name: the file's, and the stack's when the file
    holds more than one."""
    var from_slash = path.rfind("/") + 1
    var file = String(path[byte=from_slash:])
    var dot = file.rfind(".")
    var name = file.copy()
    if dot > 0:
        name = String(file[byte=:dot])
    if count == 1:
        return name^
    return name + " " + stack


def read_mixamo(
    path: String,
    bones: List[NodeId],
    rig: HumanoidRig,
    options: MixamoOptions = MixamoOptions(),
) raises -> List[AnimationClip]:
    """Read a Mixamo `.fbx` file into clips of the humanoid.

    The first needed bones are the Hips, and the Arm, ForeArm, UpLeg, Leg
    and Foot of each side. Each clip takes its name from the file, as
    `Walking.fbx` gives `Walking`. A file with more than one animation
    adds the animation's name.

    Args:
        path: The file, binary or ASCII.
        bones: One node per joint of the humanoid, in the order of the
            joints.
        rig: The rig the bones were placed from.
        options: Whether the hips stay in place, and the sampling rate.

    Returns:
        The clips.

    Raises:
        Error: If the file cannot be read as FBX, or as `retarget_mixamo`
            raises.
    """
    var scene = Scene()
    var assets = Assets()
    var source = read_fbx(path, scene, assets)
    var clips = retarget_mixamo(scene, source, bones, rig, options)
    for index in range(len(clips)):  # pragma: no branch
        clips[index].name = _clip_name(path, clips[index].name, len(clips))
    return clips^
