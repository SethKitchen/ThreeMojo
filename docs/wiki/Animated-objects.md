# Animated objects

This page covers the animated objects of three.js's `examples/jsm/misc/`. They are two morph target players, two Quake II characters and a gyroscope. Each one drives meshes and nodes that are already in the scene.

| Module | three.js |
|---|---|
| `objects/morph_anim_mesh.mojo` | `MorphAnimMesh` |
| `objects/morph_blend_mesh.mojo` | `MorphBlendMesh` |
| `objects/md2_character.mojo` | `MD2Character`, `MD2CharacterComplex` |
| `objects/gyroscope.mojo` | `Gyroscope` |

The tests compare every morph weight, place, turn and speed with three.js 0.180 in Node. `assets/md2/three_characters.mjs` writes the numbers.

## MorphAnimMesh

A `MorphAnimMesh` plays one morph target clip at a time on one mesh. It has its own mixer.

```mojo
var anim = MorphAnimMesh(MeshIndex(0), clips^)
anim.play_animation("run", 6)
anim.update_animation(scene, Duration(0.1, SECOND))
```

`play_animation(label, fps)` stops the clip that plays and plays the clip of that name. The clip runs at `fps` frames a second: its tracks times `fps`, over its duration. `set_direction_forward` and `set_direction_backward` set the mixer's time scale to one or minus one.

three.js finds the clips in the geometry's `animations`. A geometry here holds no clips, so you give them. `md2_clip` and `create_clips_from_morph_target_sequences` make them. A label that no clip has raises.

## MorphBlendMesh

A `MorphBlendMesh` plays runs of a mesh's morph targets as flip-books, and blends them by weight.

```mojo
var blend = MorphBlendMesh(MeshIndex(0), scene)
blend.auto_create_animations(scene, 6)
_ = blend.play_animation("run")
blend.update(scene, 0.1)
```

Each animation is a range of targets played at `fps` frames a second. At each `update`, an active animation finds the frame for its time. It gives that frame and the frame before it weights that cross-fade. Its `weight` scales both.

A new blend mesh has one animation, `__default`, of every target. `auto_create_animations` adds one animation for each word that starts the targets' names. So `run1` to `run6` make the animation `run`. Call `update_morph_targets` on the mesh first, because the names come from its `morph_target_dictionary`.

| Member | three.js |
|---|---|
| `create_animation(name, start, end, fps)` | `createAnimation` |
| `play_animation(name) -> Bool`, `stop_animation(name)` | `playAnimation`, `stopAnimation` |
| `set_animation_direction_forward(name)`, `set_animation_direction_backward(name)` | The same names |
| `set_animation_fps`, `set_animation_duration`, `set_animation_weight`, `set_animation_time` | The same names |
| `get_animation_time(name)`, `get_animation_duration(name)` | The same names |
| `mirrored_loop` on an animation | `mirroredLoop`: play back and forth |

A name that no animation has is passed over, as in three.js. `play_animation` returns False for it, where three.js warns. The times are in seconds, as `Float64`, as three.js keeps them.

## MD2Character

An `MD2Character` is a body and its weapons, each an MD2 model on a node under one `root`. A mixer plays the model's clips.

```mojo
var character = MD2Character(
    scene, assets, read_md2("body.md2"), weapons, names, skins, weapon_skins
)
character.set_weapon(scene, 0)
character.set_animation("run")
character.update(scene, Duration(0.1, SECOND))
```

Each part has a textured `LAMBERT` material and a wireframe one, and turns a quarter turn about y. The root rises so that the body's lowest point is on the ground. The weapons do not show until `set_weapon`. The last weapon is the active one, as in three.js.

`set_animation` plays a clip on the body. The weapon plays its clip of the same name, in step with the body. `set_skin` changes the body's skin, but not while it is a wireframe. `set_wireframe` changes the body and the weapon. `set_playback_rate(rate)` sets the mixer's time scale to one over the rate.

three.js loads the models and the skins from URLs. Here you read them first, with `read_md2` and a texture loader. Then you give the models and the texture ids.

## MD2CharacterComplex

An `MD2CharacterComplex` walks, crouches, jumps and attacks. It blends one animation into the next, and moves its root.

```mojo
var character = MD2CharacterComplex(
    scene, assets, body, weapons, names, skins, weapon_skins,
    animations=Md2AnimationNames(
        "run", "stand", "jump", "attack", "crwalk", "crstand", "crattack"
    ),
)
var asked = Md2Controls()
asked.move_forward = True
character.controls = asked^
character.update(scene, Duration(0.1, SECOND))
```

Each part plays its frames with a `MorphBlendMesh`. `set_animation` starts a blend that takes `transition_frames` updates. `update` moves the character by `controls`, picks the animation for what the controls ask, and blends.

| Member | Default | Meaning |
|---|---|---|
| `walk_speed`, `crouch_speed` | 275, 137.5 | The top speeds, as a `Velocity`. |
| `front_acceleration`, `back_acceleration`, `front_deceleration` | 600 | How fast it speeds up and slows down, as an `Acceleration`. |
| `angular_speed` | 2.5 radians a second | How fast it turns, as an `AngularVelocity`. |
| `transition_frames` | 15 | How many updates a blend takes. |
| `speed`, `body_orientation` | 0 | How fast it goes, and which way it faces. |

The speeds are in three.js's units a second, which here are meters a second. `setPlaybackRate` is not ported, because three.js sets fields that nothing reads.

## Gyroscope

`gyroscope()` returns a node that keeps its own rotation in the world. `Scene.update` gives it the position and the scale of its parents, and its own rotation. Its children follow it.

```mojo
var spinner = gyroscope()
var id = scene.attach(spinner^, car)
_ = scene.attach(camera_node^, id)
```

three.js's example hangs a camera on a gyroscope under a car. The camera follows the car, but it does not turn with it.

A gyroscope is a node of `GYROSCOPE_TYPE`. three.js writes it to JSON as `Object3D`, and this port does the same. `Scene.attach` treats it as a plain node, because three.js's `Gyroscope` does not change `updateWorldMatrix`.
