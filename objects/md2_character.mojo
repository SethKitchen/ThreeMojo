# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Quake II characters with weapons and skins, from three.js
`examples/jsm/misc/MD2Character.js` and `MD2CharacterComplex.js`.

A character is a body and a list of weapons, each an MD2 model on a node
under one `root`. Each part has a textured material and a wireframe one,
both `LAMBERT`, and is turned a quarter turn about y, as three.js turns it.
The root is lifted so the body's lowest point stands on the ground.

`MD2Character` plays the model's clips with a mixer: `set_animation`
plays a clip on the body, and the weapon plays its clip of the same name in
step. `MD2CharacterComplex` plays the frames with a `MorphBlendMesh` for
each part, blends from one animation to the next over `transition_frames`
updates, and moves the root by `controls`.

three.js loads the models and the skins from URLs, and calls back when
they are in. Here the caller reads them first, with `read_md2` and a
texture loader, and gives the models and the texture ids.

**Where this differs from three.js.** `MD2CharacterComplex`'s
`setPlaybackRate` sets fields that nothing in three.js reads, so it is
left out. A weapon or a skin index past the end shows no weapon, and no
skin, as three.js's `undefined` does.
"""

from animation.animation_clip import AnimationClip, find_by_name
from animation.animation_mixer import AnimationAction, AnimationMixer
from animation.keyframe_track import MeshIndex
from core.assets import Assets
from core.buffer_geometry import POSITION
from core.geometry_store import GeometryId
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from loaders.md2 import Md2Model, md2_clip
from materials.material import LAMBERT, Material, MaterialId
from objects.mesh import Mesh
from objects.morph_blend_mesh import MorphBlendMesh
from render.framebuffer import Color
from render.texture_store import NO_TEXTURE, TextureId
from std.math import cos, exp2, sin
from units.si import (
    Acceleration,
    Angle,
    AngularVelocity,
    DEGREE,
    Duration,
    METER,
    METER_PER_SECOND,
    METER_PER_SECOND_SQUARED,
    RADIAN,
    RADIAN_PER_SECOND,
    SECOND,
    Velocity,
)

# three.js's wireframe color, `0xffaa00`.
comptime WIREFRAME_COLOR = Color(0xFF, 0xAA, 0x00)
# The frames a second of the clips three.js's `MD2Loader` makes.
comptime MD2_CLIP_FPS = Float64(10)


struct Md2Part(Copyable, Movable):
    """One model of a character: its mesh, its node and its two
    materials, three.js's `materialTexture` and `materialWireframe`."""

    var mesh: Int
    var node: NodeId
    var textured: MaterialId
    var wireframe: MaterialId


def _lowest(model: Md2Model) raises -> Float32:
    """Return the lowest y of a model's first frame, three.js's
    `Box3.setFromBufferAttribute( position ).min.y`."""
    ref data = model.geometry.attribute_view(String(POSITION)).data
    var low = Float32(0)
    for at in range(1, len(data), 3):
        if at == 1 or data[at] < low:
            low = data[at]
    return low


def _make_part(
    mut scene: Scene,
    mut assets: Assets,
    root: NodeId,
    geometry: GeometryId,
    skin: TextureId,
    scale: Float32,
    visible: Bool,
    name: String,
) raises -> Md2Part:
    """Add one model under the root, three.js's `createPart` and its
    caller: a quarter turn about y, `scale`, and two materials."""
    var wire = Material(WIREFRAME_COLOR, kind=LAMBERT)
    wire.wireframe = True
    var textured = Material(Color(255, 255, 255), kind=LAMBERT)
    textured.map = skin
    var wire_id = assets.materials.add(wire^)
    var textured_id = assets.materials.add(textured^)
    var node = Object3D()
    node.set_euler(
        Angle(0.0, DEGREE), Angle(-90.0, DEGREE), Angle(0.0, DEGREE)
    )
    node.set_scale(scale, scale, scale)
    node.visible = visible
    node.name = name
    var at = scene.attach(node^, root)
    var mesh = Mesh(
        geometry, textured_id, at, cast_shadow=True, receive_shadow=True
    )
    mesh.update_morph_targets(assets.geometries.get(geometry))
    var index = len(scene.meshes)
    scene.add_mesh(mesh)
    return Md2Part(index, at, textured_id, wire_id)


def _skin(skins: List[TextureId], index: Int) -> TextureId:
    """Return a skin, or no texture past the end, three.js's `undefined`."""
    if index < 0 or index >= len(skins):
        return NO_TEXTURE
    return skins[index]


def _wear(
    mut scene: Scene, part: Md2Part, wireframe: Bool
):
    """Give a part its wireframe or its textured material."""
    scene.meshes[part.mesh].material = (
        part.wireframe if wireframe else part.textured
    )


struct MD2Character(Movable):
    """A character whose clips a mixer plays, three.js's `MD2Character`."""

    var scale: Float32
    # three.js's `animationFPS`, which its character keeps and does not
    # read.
    var animation_fps: Float64
    var root: NodeId
    var body: Md2Part
    var weapons: List[Md2Part]
    # The weapon that shows, as its place in `weapons`, three.js's
    # `meshWeapon`: the last one made until `set_weapon`, or -1 for none.
    var weapon: Int
    var skins_body: List[TextureId]
    var skins_weapon: List[TextureId]
    # Each part's clips, three.js's `geometry.animations`: the body's, then
    # each weapon's.
    var body_clips: List[AnimationClip]
    var weapon_clips: List[List[AnimationClip]]
    var mixer: AnimationMixer
    # The name of the body's first clip, three.js's
    # `activeAnimationClipName`, and the clip `set_animation` last asked
    # for, its `activeClipName`.
    var active_animation_clip_name: String
    var active_clip_name: String
    # The action each part plays, or -1.
    var body_action: Int
    var weapon_action: Int

    def __init__(
        out self,
        mut scene: Scene,
        mut assets: Assets,
        body: Md2Model,
        weapons: List[Md2Model],
        weapon_names: List[String],
        var skins_body: List[TextureId],
        var skins_weapon: List[TextureId],
        scale: Float32 = 1,
        parent: NodeId = NO_PARENT,
    ) raises:
        """Build a character in a scene, three.js's `loadParts` once every
        part is in.

        Args:
            scene: The scene to add the root and the parts to.
            assets: Where the geometries and the materials go.
            body: The body's model.
            weapons: Each weapon's model.
            weapon_names: Each weapon's name, three.js's file name.
            skins_body: The body's skins; the first is worn.
            skins_weapon: Each weapon's skin.
            scale: The size of every part, three.js's `scale`.
            parent: The node the root hangs from.

        Raises:
            Error: If there is not one name a weapon, or a model's clips
                cannot be made.
        """
        if len(weapon_names) != len(weapons):
            raise Error("An MD2 character needs one name a weapon")
        self.scale = scale
        self.animation_fps = 6
        var root = Object3D()
        root.set_position(0, -scale * _lowest(body), 0)
        if parent != NO_PARENT:
            self.root = scene.attach(root^, parent)
        else:
            self.root = scene.add(root^)
        self.skins_body = skins_body^
        self.skins_weapon = skins_weapon^
        var shape = assets.geometries.add(body.geometry.copy())
        self.body = _make_part(
            scene,
            assets,
            self.root,
            shape,
            _skin(self.skins_body, 0),
            scale,
            True,
            "",
        )
        self.body_clips = _clips(body, self.body.mesh)
        self.weapons = List[Md2Part]()
        self.weapon_clips = List[List[AnimationClip]]()
        for at in range(len(weapons)):
            var held = assets.geometries.add(weapons[at].geometry.copy())
            var part = _make_part(
                scene,
                assets,
                self.root,
                held,
                _skin(self.skins_weapon, at),
                scale,
                False,
                weapon_names[at],
            )
            self.weapon_clips.append(_clips(weapons[at], part.mesh))
            self.weapons.append(part^)
        self.weapon = len(self.weapons) - 1
        self.active_animation_clip_name = String()
        if len(self.body_clips) > 0:
            self.active_animation_clip_name = self.body_clips[0].name
        self.active_clip_name = String()
        self.mixer = AnimationMixer()
        self.body_action = -1
        self.weapon_action = -1

    def set_playback_rate(mut self, rate: Float32):
        """Play the clips slower or faster, three.js's `setPlaybackRate`:
        the mixer's time scale goes to one over the rate, or to zero for a
        rate of zero.

        Args:
            rate: How many times as long the clips take.
        """
        self.mixer.time_scale = 1 / rate if rate != 0 else Float32(0)

    def set_wireframe(self, mut scene: Scene, wireframe: Bool):
        """Draw the body and the weapon as wireframes, or textured again,
        three.js's `setWireframe`.

        Args:
            scene: The scene the parts are in.
            wireframe: True for the wireframes.
        """
        _wear(scene, self.body, wireframe)
        if self.weapon >= 0:
            _wear(scene, self.weapons[self.weapon], wireframe)

    def set_skin(self, scene: Scene, mut assets: Assets, index: Int) raises:
        """Put a skin on the body, three.js's `setSkin`. Nothing changes
        while the body is a wireframe.

        Args:
            scene: The scene the parts are in.
            assets: Where the materials are.
            index: Which of `skins_body`. Past the end is no skin.

        Raises:
            Error: If the body's material is not in the assets.
        """
        var worn = scene.meshes[self.body.mesh].material
        if assets.materials.get(worn).wireframe:
            return
        assets.materials.materials[worn.value].map = _skin(self.skins_body, index)

    def set_weapon(mut self, mut scene: Scene, index: Int) raises:
        """Show one weapon and hide the rest, three.js's `setWeapon`, and
        play its clip in step with the body's.

        Args:
            scene: The scene the parts are in.
            index: Which weapon. Past the end hides them all.

        Raises:
            Error: If the weapon's clip cannot be played.
        """
        for at in range(len(self.weapons)):
            scene.node(self.weapons[at].node).visible = False
        if index < 0 or index >= len(self.weapons):
            return
        scene.node(self.weapons[index].node).visible = True
        self.weapon = index
        self.sync_weapon_animation()

    def set_animation(mut self, clip_name: String) raises:
        """Play a clip on the body and the weapon, three.js's
        `setAnimation`.

        Args:
            clip_name: The clip. Nothing plays on a part without it.

        Raises:
            Error: If a clip cannot be played.
        """
        if self.body_action >= 0:
            self.mixer.action(self.body_action).stop()
            self.body_action = -1
        var found = find_by_name(self.body_clips, clip_name)
        if found:
            self.body_action = self._action(self.body_clips[found.value()])
            self.mixer.action(self.body_action).play()
        self.active_clip_name = clip_name
        self.sync_weapon_animation()

    def sync_weapon_animation(mut self) raises:
        """Play the weapon's clip of the body's clip's name, in step with
        the body, three.js's `syncWeaponAnimation`.

        Raises:
            Error: If the clip cannot be played.
        """
        if self.weapon < 0:
            return
        if self.weapon_action >= 0:
            self.mixer.action(self.weapon_action).stop()
            self.weapon_action = -1
        var found = find_by_name(
            self.weapon_clips[self.weapon], self.active_clip_name
        )
        if not found:
            return
        self.weapon_action = self._action(
            self.weapon_clips[self.weapon][found.value()]
        )
        if self.body_action >= 0:
            self.mixer.sync_with(self.weapon_action, self.body_action)
        self.mixer.action(self.weapon_action).play()

    def _action(mut self, clip: AnimationClip) raises -> Int:
        """Return the mixer's action on a clip, made the first time, as
        three.js's `clipAction` caches one."""
        for at in range(self.mixer.action_count()):
            ref held = self.mixer.actions[at].clip
            if held.name == clip.name and held.tracks[0].target == clip.tracks[
                0
            ].target:
                return at
        return self.mixer.add(AnimationAction(clip.copy()))

    def update(mut self, mut scene: Scene, delta: Duration) raises:
        """Move the clips on, three.js's `update`.

        Args:
            scene: The scene the parts are in.
            delta: The time since the last update.

        Raises:
            Error: As `AnimationMixer.update` does.
        """
        self.mixer.update(scene, delta)


def _clips(model: Md2Model, mesh: Int) raises -> List[AnimationClip]:
    """Return a model's clips on a mesh, as three.js's `MD2Loader` makes
    them: ten frames a second, and looping."""
    var clips = List[AnimationClip]()
    for at in range(len(model.animations)):
        if len(model.animations[at].frames) < 3:
            # `md2_clip` refuses a clip three.js makes with keys at one
            # time; such a clip is not played here.
            continue
        clips.append(md2_clip(model, at, MeshIndex(mesh), MD2_CLIP_FPS))
    return clips^


struct Md2Controls(Copyable, Movable):
    """What a complex character is asked to do, three.js's `controls`
    object."""

    var move_forward: Bool
    var move_backward: Bool
    var move_left: Bool
    var move_right: Bool
    var crouch: Bool
    var jump: Bool
    var attack: Bool

    def __init__(out self):
        """Ask for nothing."""
        self.move_forward = False
        self.move_backward = False
        self.move_left = False
        self.move_right = False
        self.crouch = False
        self.jump = False
        self.attack = False


struct Md2AnimationNames(Copyable, Movable):
    """Which animation a complex character plays for each thing it does,
    three.js's `animations` object."""

    var move: String
    var idle: String
    var jump: String
    var attack: String
    var crouch_move: String
    var crouch_idle: String
    var crouch_attack: String

    def __init__(
        out self,
        move: String,
        idle: String,
        jump: String,
        attack: String,
        crouch_move: String,
        crouch_idle: String,
        crouch_attack: String,
    ):
        """Name each animation.

        Args:
            move: While it moves.
            idle: While it stands.
            jump: While it jumps.
            attack: While it attacks.
            crouch_move: While it moves crouched.
            crouch_idle: While it stands crouched.
            crouch_attack: While it attacks crouched.
        """
        self.move = move
        self.idle = idle
        self.jump = jump
        self.attack = attack
        self.crouch_move = crouch_move
        self.crouch_idle = crouch_idle
        self.crouch_attack = crouch_attack


def _ease_out(k: Float32) -> Float32:
    """Return three.js's `exponentialEaseOut`: one at one, and
    `1 - 2^(-10 k)` elsewhere."""
    if k == 1:
        return 1
    return -exp2(-10 * k) + 1


def _clamp(value: Float32, low: Float32, high: Float32) -> Float32:
    """Return three.js's `MathUtils.clamp`."""
    return max(low, min(high, value))


struct MD2CharacterComplex(Movable):
    """A character that walks, crouches, jumps and attacks, blending one
    animation into the next, three.js's `MD2CharacterComplex`."""

    var scale: Float32
    # The frames a second each part's animations play at.
    var animation_fps: Float64
    # How many updates a blend from one animation to the next takes.
    var transition_frames: Int
    var max_speed: Velocity
    var max_reverse_speed: Velocity
    var front_acceleration: Acceleration
    var back_acceleration: Acceleration
    var front_deceleration: Acceleration
    var angular_speed: AngularVelocity
    var root: NodeId
    var body: Md2Part
    var body_blend: MorphBlendMesh
    var weapons: List[Md2Part]
    var weapon_blends: List[MorphBlendMesh]
    # The weapon that shows, or -1, three.js's `meshWeapon`.
    var weapon: Int
    # What the character is asked to do, or none for standing by.
    var controls: Optional[Md2Controls]
    var skins_body: List[TextureId]
    var skins_weapon: List[TextureId]
    # The skin `set_skin` last put on, or -1, three.js's `currentSkin`.
    var current_skin: Int
    var animations: Optional[Md2AnimationNames]
    var speed: Velocity
    # Which way the character faces, about y.
    var body_orientation: Angle
    var walk_speed: Velocity
    var crouch_speed: Velocity
    # The animation that plays and the one it blends from, or empty.
    var active_animation: String
    var old_animation: String
    # How many updates the blend has to go.
    var blend_counter: Int

    def __init__(
        out self,
        mut scene: Scene,
        mut assets: Assets,
        body: Md2Model,
        weapons: List[Md2Model],
        weapon_names: List[String],
        var skins_body: List[TextureId],
        var skins_weapon: List[TextureId],
        animations: Optional[Md2AnimationNames] = None,
        walk_speed: Velocity = Velocity(275.0, METER_PER_SECOND),
        crouch_speed: Velocity = Velocity(137.5, METER_PER_SECOND),
        scale: Float32 = 1,
        parent: NodeId = NO_PARENT,
    ) raises:
        """Build a character in a scene, three.js's `loadParts` once every
        part is in.

        Args:
            scene: The scene to add the root and the parts to.
            assets: Where the geometries and the materials go.
            body: The body's model.
            weapons: Each weapon's model.
            weapon_names: Each weapon's name.
            skins_body: The body's skins; the first is worn.
            skins_weapon: Each weapon's skin.
            animations: Which animation plays for each thing it does,
                three.js's `config.animations`, or none to play nothing.
            walk_speed: Its top speed, three.js's `config.walkSpeed`.
            crouch_speed: Its top speed crouched.
            scale: The size of every part.
            parent: The node the root hangs from.

        Raises:
            Error: If there is not one name a weapon.
        """
        if len(weapon_names) != len(weapons):
            raise Error("An MD2 character needs one name a weapon")
        self.scale = scale
        self.animation_fps = 6
        self.transition_frames = 15
        self.max_speed = Velocity(275.0, METER_PER_SECOND)
        self.max_reverse_speed = Velocity(-275.0, METER_PER_SECOND)
        self.front_acceleration = Acceleration(600.0, METER_PER_SECOND_SQUARED)
        self.back_acceleration = Acceleration(600.0, METER_PER_SECOND_SQUARED)
        self.front_deceleration = Acceleration(600.0, METER_PER_SECOND_SQUARED)
        self.angular_speed = AngularVelocity(2.5, RADIAN_PER_SECOND)
        self.controls = None
        self.current_skin = -1
        self.animations = animations
        self.speed = Velocity(0.0, METER_PER_SECOND)
        self.body_orientation = Angle(0.0, RADIAN)
        self.walk_speed = walk_speed
        self.crouch_speed = crouch_speed
        self.active_animation = String()
        self.old_animation = String()
        self.blend_counter = 0
        var root = Object3D()
        root.set_position(0, -scale * _lowest(body), 0)
        if parent != NO_PARENT:
            self.root = scene.attach(root^, parent)
        else:
            self.root = scene.add(root^)
        self.skins_body = skins_body^
        self.skins_weapon = skins_weapon^
        var shape = assets.geometries.add(body.geometry.copy())
        self.body = _make_part(
            scene,
            assets,
            self.root,
            shape,
            _skin(self.skins_body, 0),
            scale,
            True,
            "",
        )
        self.body_blend = _blend(scene, self.body, self.animation_fps)
        self.weapons = List[Md2Part]()
        self.weapon_blends = List[MorphBlendMesh]()
        for at in range(len(weapons)):
            var held = assets.geometries.add(weapons[at].geometry.copy())
            var part = _make_part(
                scene,
                assets,
                self.root,
                held,
                _skin(self.skins_weapon, at),
                scale,
                False,
                weapon_names[at],
            )
            self.weapon_blends.append(_blend(scene, part, self.animation_fps))
            self.weapons.append(part^)
        self.weapon = len(self.weapons) - 1

    def enable_shadows(self, mut scene: Scene, enable: Bool):
        """Cast and take shadows, or not, three.js's `enableShadows`.

        Args:
            scene: The scene the parts are in.
            enable: True to cast and take them.
        """
        var parts = self._parts()
        for at in range(len(parts)):
            scene.meshes[parts[at]].cast_shadow = enable
            scene.meshes[parts[at]].receive_shadow = enable

    def set_visible(self, mut scene: Scene, enable: Bool) raises:
        """Show or hide every part, three.js's `setVisible`.

        Args:
            scene: The scene the parts are in.
            enable: True to show them.

        Raises:
            Error: If a part's node is not in the scene.
        """
        scene.node(self.body.node).visible = enable
        for at in range(len(self.weapons)):
            scene.node(self.weapons[at].node).visible = enable

    def _parts(self) -> List[Int]:
        """Return every part's mesh, three.js's `meshes`."""
        var parts: List[Int] = [self.body.mesh]
        for at in range(len(self.weapons)):
            parts.append(self.weapons[at].mesh)
        return parts^

    def set_wireframe(self, mut scene: Scene, wireframe: Bool):
        """Draw the body and the weapon as wireframes, or textured again,
        three.js's `setWireframe`.

        Args:
            scene: The scene the parts are in.
            wireframe: True for the wireframes.
        """
        _wear(scene, self.body, wireframe)
        if self.weapon >= 0:
            _wear(scene, self.weapons[self.weapon], wireframe)

    def set_skin(mut self, scene: Scene, mut assets: Assets, index: Int) raises:
        """Put a skin on the body, three.js's `setSkin`. Nothing changes
        while the body is a wireframe.

        Args:
            scene: The scene the parts are in.
            assets: Where the materials are.
            index: Which of `skins_body`. Past the end is no skin.

        Raises:
            Error: If the body's material is not in the assets.
        """
        var worn = scene.meshes[self.body.mesh].material
        if assets.materials.get(worn).wireframe:
            return
        assets.materials.materials[worn.value].map = _skin(self.skins_body, index)
        self.current_skin = index

    def set_weapon(mut self, mut scene: Scene, index: Int) raises:
        """Show one weapon and hide the rest, three.js's `setWeapon`, and
        play the body's animation on it from the body's time.

        Args:
            scene: The scene the parts are in.
            index: Which weapon. Past the end hides them all.

        Raises:
            Error: If a weapon's node is not in the scene.
        """
        for at in range(len(self.weapons)):
            scene.node(self.weapons[at].node).visible = False
        if index < 0 or index >= len(self.weapons):
            return
        scene.node(self.weapons[index].node).visible = True
        self.weapon = index
        if self.active_animation != "":
            _ = self.weapon_blends[index].play_animation(self.active_animation)
            self.weapon_blends[index].set_animation_time(
                self.active_animation,
                self.body_blend.get_animation_time(self.active_animation),
            )

    def set_animation(mut self, name: String):
        """Start blending into an animation, three.js's `setAnimation`.

        Args:
            name: The animation. Nothing happens for the one that plays, or
                for an empty name.
        """
        if name == self.active_animation or name == "":
            return
        self.body_blend.set_animation_weight(name, 0)
        _ = self.body_blend.play_animation(name)
        self.old_animation = self.active_animation
        self.active_animation = name
        self.blend_counter = self.transition_frames
        if self.weapon >= 0:
            self.weapon_blends[self.weapon].set_animation_weight(name, 0)
            _ = self.weapon_blends[self.weapon].play_animation(name)

    def update(mut self, mut scene: Scene, delta: Duration) raises:
        """Move, pick the animation, and blend, three.js's `update`.

        Args:
            scene: The scene the parts are in.
            delta: The time since the last update.

        Raises:
            Error: If the time is not a number, or the root is not in the
                scene.
        """
        if self.controls:
            self.update_movement_model(scene, delta)
        if self.animations:
            self.update_behaviors()
            self.update_animations(scene, delta)

    def update_animations(mut self, mut scene: Scene, delta: Duration) raises:
        """Blend from the old animation to the active one, three.js's
        `updateAnimations`.

        Args:
            scene: The scene the parts are in.
            delta: The time since the last update.

        Raises:
            Error: If the time is not a number.
        """
        var mix = Float32(1)
        if self.blend_counter > 0:
            mix = Float32(self.transition_frames - self.blend_counter) / Float32(
                self.transition_frames
            )
            self.blend_counter -= 1
        var seconds = Float64(delta.to(SECOND))
        self.body_blend.update(scene, seconds)
        self.body_blend.set_animation_weight(self.active_animation, mix)
        self.body_blend.set_animation_weight(self.old_animation, 1 - mix)
        if self.weapon >= 0:
            self.weapon_blends[self.weapon].update(scene, seconds)
            self.weapon_blends[self.weapon].set_animation_weight(
                self.active_animation, mix
            )
            self.weapon_blends[self.weapon].set_animation_weight(
                self.old_animation, 1 - mix
            )

    def update_behaviors(mut self):
        """Pick the animation for what the controls ask, three.js's
        `updateBehaviors`."""
        if not self.controls or not self.animations:
            return
        var controls = self.controls.value().copy()
        var names = self.animations.value().copy()
        var move = names.move
        var idle = names.idle
        if controls.crouch:
            move = names.crouch_move
            idle = names.crouch_idle
        if controls.jump:
            move = names.jump
            idle = names.jump
        if controls.attack:
            if controls.crouch:
                move = names.crouch_attack
                idle = names.crouch_attack
            else:
                move = names.attack
                idle = names.attack
        var moving = (
            controls.move_forward
            or controls.move_backward
            or controls.move_left
            or controls.move_right
        )
        if moving and self.active_animation != move:
            self.set_animation(move)
        var slow = abs(self.speed.to(METER_PER_SECOND)) < 0.2 * self.max_speed.to(
            METER_PER_SECOND
        )
        if slow and not moving and self.active_animation != idle:
            self.set_animation(idle)
        if controls.move_forward:
            self._direction(True)
        if controls.move_backward:
            self._direction(False)

    def _direction(mut self, forward: Bool):
        """Play the active and the old animation forward or back."""
        var names: List[String] = [self.active_animation, self.old_animation]
        for at in range(2):
            if forward:
                self.body_blend.set_animation_direction_forward(names[at])
            else:
                self.body_blend.set_animation_direction_backward(names[at])
            if self.weapon >= 0:
                if forward:
                    self.weapon_blends[
                        self.weapon
                    ].set_animation_direction_forward(names[at])
                else:
                    self.weapon_blends[
                        self.weapon
                    ].set_animation_direction_backward(names[at])

    def update_movement_model(mut self, mut scene: Scene, delta: Duration) raises:
        """Speed up, slow down, turn and move the root, three.js's
        `updateMovementModel`.

        Args:
            scene: The scene the root is in.
            delta: The time since the last update.

        Raises:
            Error: If the root is not in the scene.
        """
        if not self.controls:
            return
        var controls = self.controls.value().copy()
        var dt = delta.to(SECOND)
        var top = (
            self.crouch_speed if controls.crouch else self.walk_speed
        ).to(METER_PER_SECOND)
        self.max_speed = Velocity(top, METER_PER_SECOND)
        self.max_reverse_speed = Velocity(-top, METER_PER_SECOND)
        var speed = self.speed.to(METER_PER_SECOND)
        var front = self.front_acceleration.to(METER_PER_SECOND_SQUARED)
        var back = self.back_acceleration.to(METER_PER_SECOND_SQUARED)
        var slow = self.front_deceleration.to(METER_PER_SECOND_SQUARED)
        var turn = self.angular_speed.to(RADIAN_PER_SECOND)
        var facing = self.body_orientation.to(RADIAN)
        if controls.move_forward:
            speed = _clamp(speed + dt * front, -top, top)
        if controls.move_backward:
            speed = _clamp(speed - dt * back, -top, top)
        if controls.move_left:
            facing += dt * turn
            speed = _clamp(speed + dt * front, -top, top)
        if controls.move_right:
            facing -= dt * turn
            speed = _clamp(speed + dt * front, -top, top)
        if not (controls.move_forward or controls.move_backward):
            if speed > 0:
                var k = _ease_out(speed / top)
                speed = _clamp(speed - k * dt * slow, 0, top)
            else:
                var k = _ease_out(speed / -top)
                speed = _clamp(speed + k * dt * back, -top, 0)
        self.speed = Velocity(speed, METER_PER_SECOND)
        self.body_orientation = Angle(facing, RADIAN)
        var forward = speed * dt
        ref root = scene.node(self.root)
        root.position.x += sin(facing) * forward
        root.position.z += cos(facing) * forward
        root.set_euler(
            Angle(0.0, RADIAN), Angle(facing, RADIAN), Angle(0.0, RADIAN)
        )


def _blend(
    scene: Scene, part: Md2Part, fps: Float64
) raises -> MorphBlendMesh:
    """Return a part's blend mesh with an animation for each of its frame
    runs, three.js's `_createPart` and `autoCreateAnimations`."""
    var blend = MorphBlendMesh(MeshIndex(part.mesh), scene)
    blend.auto_create_animations(scene, fps)
    return blend^
