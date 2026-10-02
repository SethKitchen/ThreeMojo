# Game humanoid

A game humanoid is one person's skin on a skeleton, ready to animate. Build it once, bake it to a glTF file, and load the file in the game. It draws at more than 24 frames a second.

For engineering use and representation limits, see [Humanoid fidelity](Humanoid-fidelity).

```mojo
from extensions.humanoid.rig.clips import walk_clip
from extensions.humanoid.rig.game import add_game_humanoid

var person = add_game_humanoid(scene, assets, root, spec, 10000)
var mixer = AnimationMixer()
var walk = mixer.add(AnimationAction(walk_clip(person.bones, person.rig)))
mixer.action(walk).play()
```

Each frame, call `mixer.update(scene, delta)`, then `scene.update()`, then render. The renderer's skinning moves the skin with the bones. See [Skinning](Skinning) and [Animation](Animation).

## The skeleton

The rig has nineteen joints. Each joint is a bone, a scene node named as a glTF humanoid names it, as `"hips"` or `"rightShin"`.

| Joints | Where they stand |
|---|---|
| `HIPS` | The pelvis frame's origin, between the hip joints. It is the root. |
| `SPINE`, `CHEST` | A third and two thirds of the way from the hips to the neck. |
| `NECK`, `HEAD` | The seventh cervical vertebra and the atlas, where the skull nods. |
| `*_UPPER_ARM`, `*_FOREARM`, `*_HAND` | The arm frame's shoulder, elbow and wrist. |
| `*_THIGH`, `*_SHIN`, `*_FOOT` | The femoral head, the knee's joint line and the tibial plafond. |
| `*_TOES` | The ball of the foot: seven tenths of the way from the ankle to the toes' tip. |

`humanoid_rig(spec, skin)` places the joints from the anatomy. The skin marks the crown, the fingertips and the toes' tip. The joints stand where a genome puts them, so a rig fits every body.

## The skin and its weights

`add_game_humanoid` builds three skinned meshes on one skeleton: the body's skin and each hand's. The eyes and the scalp's hair hang from the head's bone, so they turn with it. With `guides`, it grows strands of hair as well.

`skin_weights` binds a skin to the bones. It measures distance over the skin, not through the air. So a part is turned only by the bones it joins through the skin.

Positions must be finite. Welding multiplies each coordinate by `1e5` in
Float32 and truncates toward zero. The product must be at least `Int.MIN`
and less than `-Int.MIN` (from `-2^63` inclusive to `2^63` exclusive).
`skin_weights` raises an error before it changes any skin attribute if a
position is outside this domain. Hash products wrap modulo `2^64`; hash
collisions do not join distinct grid positions. Ordinary anatomical
positions keep the same welds and triangle neighbors.

1. Each bone takes the vertices beside its middle that lie nearest it, in the bone's own thicknesses. A chest is thicker than an upper arm, so it keeps the ribs' side.
2. A bone keeps only its largest patch of these. A patch apart from it lies on another part, as the thigh beside a hanging hand.
3. From each patch, the nearness spreads along the triangles' edges.
4. A vertex weighs each bone by the inverse fourth power of that distance plus 3 cm. The four heaviest bones keep their weights, which add up to one.

A limb's bones never turn the far side of the midline. Each hand is turned only by its own forearm and hand. The body's skin is not turned by the hands, whose own meshes draw them.

The thighs touch, so the skin over them is one surface. For a game the body's skin is meshed with a slot between the legs, about 3 cm wide and rounded. `body_skin_mesh(..., parted=)` cuts it. `part_legs` then gives each leg its own triangles below the crotch.

## The clips

`extensions.humanoid.rig.clips` makes five clips for any rig. Each samples a pose 30 times a second. A pose is each joint's flexion, twist and lean, and how far the hips move.

| Clip | Length | The motion |
|---|---|---|
| `idle_clip` | 4 s, loops | Breathing, a slow shift of the weight, and a glance to each side. |
| `walk_clip` | 1.1 s, loops | A stride: the hip from 26 degrees forward to 10 back, the knee to 60 in the swing, a push off the ankle, the arms against the legs. |
| `run_clip` | 0.7 s, loops | A stride with a flight, the arms bent and pumping, the trunk leaning. |
| `jump_clip` | 1.4 s, once | A crouch, a spring with the arms thrown up, a tuck, and a landing on bent knees. |
| `wave_clip` | 2 s, loops | The right arm raised and the hand waving. |

The angles follow the joint ranges of an ordinary gait (Winter 1991). The clips move in place: a game moves the humanoid's root node itself. `clip_from_poses` makes a clip from any poses.

## Baking and speed

Build the humanoid once and bake it with `write_gltf(path, scene, assets, GLB, animations=clips)`. A game loads the file with `read_gltf`, which returns the clips by name.

| Step | Time |
|---|---|
| Build at 10,000 triangles | 5.6 s |
| Bake to `.glb` | 5 ms |
| Load the `.glb` | 12 ms |
| Animate and draw one frame, 640 by 360 | 31 ms: 32 frames a second |

These were measured on four cores. Most of the build is the hair's shell, at `hair_detail` 32.

`triangles` sets the skin's budget. The body's skin takes 76 % of it, the hair's shell 12 % and each hand 6 %. A decimated skin keeps its colors: each vertex takes those of the nearest vertex of the full skin. At 20,000 triangles a frame takes 52 ms. A material with textures and light through thin skin costs about twice the time of the default Phong.

## Example

`examples/game_humanoid.mojo` bakes `out/humanoid.glb` once, then loads it and plays idle, walk, run, jump and wave, each fading into the next. It writes `out/game_humanoid.png` and prints the frame rate.

```bash
.venv/bin/mojo run -I . examples/game_humanoid.mojo
```
