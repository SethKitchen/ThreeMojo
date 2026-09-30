# Head

`add_head` attaches the neck and the head: the seven cervical vertebrae, the skull, the mandible, the teeth and the hyoid, and their joint tissues. It also attaches the muscles of the neck, the jaw and the face, and the head's vessels, nerves, lymph nodes, skin, hair and eyes.

![A six-foot male neck and head turn twice: bones, joint tissues and muscles on the left, and skin, hair and eyes on the right](out/head.png)

The neck and the head share the pelvis frame. The origin is the midpoint of the two hip joint centers. Plus y is proximal, plus x is body-right and plus z is anterior. The package is `extensions/humanoid/skeleton/head/`. The neck stands on the first thoracic vertebra of the [Torso](Torso).

This is not a three.js port. See [Extensions](Extensions).

A quality level sets how many triangles the body holds. See [Mesh quality](Mesh-quality).

## Call it

```mojo
from extensions.humanoid.athleticism import TONED
from extensions.humanoid.sex import MALE
from extensions.humanoid.spec import HumanoidSpec
from extensions.humanoid.skeleton.head.assembly import add_head
from extensions.humanoid.skeleton.head.contents import ALL, BONES
from extensions.humanoid.skeleton.head.frame import head_dimensions
from units.si import FOOT, Length

var person = HumanoidSpec(Length(6.0, FOOT), MALE, TONED)
var dims = head_dimensions(person.stature, person.sex)
var atlas = dims.centers[0]
```

`add_head` attaches the neck and the head under a parent node. Hang them from the same node as the torso. Pass `contents` to pick the layers. The layers are the arm's, and `EYES`: see [Arm](Arm#call-it). `add_body` attaches the head as well, with the torso's layers, and its one skin covers the head; see [Torso](Torso).

Pass the spec's genome to `head_dimensions` to shape the head: `head_dimensions(person.stature, person.sex, person.genome)`. See [Genome](Genome).

A bare integer is a compile error, for a bone, a part or a layer.

## Pose and size

The head sits on the atlas with the Frankfort plane level, so the eyes look straight ahead. The neck climbs from the first thoracic vertebra in a gentle lordosis.

On the six-foot male template, the top of the skull is 84.4 cm above the hip joint centers. The eyes are at 72.5 cm and the chin is at 60.5 cm. Stature scales every length. A female template is narrower and shallower, as the torso's is. The values are template parameters. They are not a cited anthropometric table.

A head keeps its size better than a body does. Across adults a head grows about as the square root of stature, so a short person's head is larger for their height. `head_scale(stature, sex)` gives the factor over what stature alone makes, and the head's frame grows the head by it about the base of the jaw. A woman's head gets a further 5%, and her neck is 10% slimmer than her frame alone makes it. The neck keeps its own size, so a shorter person's crown stands a little above the stature: about 2.5 cm at 1.63 m.

On a 1.75 m man the head measures about 56 cm round and the neck about 43 cm. On a 1.63 m woman they measure about 53 cm and 36 cm.

## Bones

| Part | Bones |
|---|---|
| Cervical vertebrae | `C1`, the atlas, to `C7` |
| Skull | `SKULL`: the vault, the base and the face |
| Jaw | `MANDIBLE` and `TEETH`, both rows |
| Throat | `HYOID` |

The atlas is a ring with two lateral masses. The axis carries the dens up through the atlas's front arch. C3 to C6 have short forked spines. The spine of C7 is long.

The vault is a thin dome of bone about seven millimeters thick. The face is one solid with the orbits and the nasal opening cut out. The mandible is a U of bone with a ramus and a condyle on each side. The condyles sit in front of the ear canals. The occipital condyles sit on the atlas.

## Joint tissues and cartilages

| Part | Role |
|---|---|
| `CERVICAL_DISCS` | A disc under each body from C2 down, the last on T1. |
| `NUCHAL_LIGAMENT` | A thin sheet in the midline, from the occiput down the spines to C7. |
| `ATLANTO_OCCIPITAL_JOINTS` | The capsules between the occipital condyles and the atlas. |
| `TEMPOROMANDIBULAR_JOINT` | The disc of one jaw joint. It is paired. |
| `LARYNX` | The thyroid cartilage's two plates and the cricoid's ring. |
| `TRACHEA` | The windpipe, down to the root of the neck. |

## Muscles

| Group | Parts |
|---|---|
| Neck | Sternocleidomastoid, upper trapezius, splenius capitis, semispinalis capitis, levator scapulae, scalenes, longus colli. |
| Throat | The infrahyoid straps and the suprahyoid floor of the mouth. |
| Jaw | Masseter and temporalis. |
| Face | Frontalis, orbicularis oculi, zygomaticus major and orbicularis oris. |

The upper trapezius meets the torso's trapezius at the base of the neck. The levator scapulae reaches the scapula's superior angle. The suprahyoid floor and the orbicularis oris cross the midline. The rest are paired.

## Vessels, nerves and lymph

The common carotid artery rises beside the trachea and forks at the level of the hyoid. The external carotid gives the facial artery and ends as the superficial temporal artery. The vertebral artery climbs through the transverse processes and loops over the atlas. The internal jugular vein runs down beside the carotid. The external jugular vein runs down across the sternocleidomastoid.

The cervical spinal cord runs up the vertebral canal. The vagus nerve runs down in the carotid sheath. The phrenic nerve runs down the front of the anterior scalene. The cervical plexus fans out from behind the sternocleidomastoid. The facial nerve fans forward through the parotid.

The deep cervical nodes lie in a chain along the internal jugular vein. The submandibular, parotid, occipital and supraclavicular nodes are small groups.

## Skin and hair

The face is a scan. The skin of the head is the mean head of the ICT Face Model Light, a morphable model learned from scans of real faces. A sculpt of even solids makes a face that looks like a doll's. The scan brings the lids, the lips, the nostrils, the folds and the ears of a real face.

`ScannedHead` fits the scan to the anatomy, in `extensions/humanoid/skeleton/head/skin/scan.mojo`:

1. The face shape genes weigh the scan's identity modes, so each face is a face of its own. The scan's eyes then land on the template's eyes. Each vertex then goes through the head's frame, as an authored point does. So the genome's face and head genes move the scan as they move the skull under it. See [Genome](Genome).
2. The ear genes warp the ears. Each ear grows about its root, its back edge stands out, and its lobe hangs lower.
3. The scan is pulled over the modeled solids like a sleeve. The solids are the vault, an ellipsoid a scalp's thickness outside the skull, and the neck, swept round its muscles. Each vertex inside them must move out along its normal. The moves are spread over the mesh until they are smooth, so the mesh stretches and does not fold.
4. The mouth and the eyes are open in the scan. The palate, the teeth and the orbits fill those spaces, so a fan of triangles closes each opening. The scan is kept as a `MeshField`, the signed distance to a mesh through a tree of boxes.

`HeadSkinField` is the smooth union of the scan and the modeled solids. The modeled anatomy stays inside the skin.

The skin's mesh is the scan's own mesh, not a mesh extracted from the field. Each vertex that the field's surface does not pass through is walked onto it. The mouth's and the eyes' sockets are drawn inside. Below the seam on the neck, 56.5 cm on the template, the skin is meshed by narrow-band surface nets, in `extensions/humanoid/skeleton/surface_nets.mojo`. The two meshes lie on one surface and overlap by a few millimeters. `add_body` joins the body's skin to the scan at the same seam.

`tools/ict_face_model.py` converts the model's OBJ files into `assets/face/ict_face.bin`. `FaceModel` reads it. The file keeps the mean head, its mesh, sixty identity modes and fifty-seven expressions, with the left and the right side apart. `FaceModel` reads only what you ask for, so a head that needs no expression loads in a few milliseconds.

| Function | Returns |
|---|---|
| `FaceModel(path, identities, expressions)` | The model, or the part of it you ask for. |
| `FaceModel.shape(identity, expression)` | Every vertex for one weight per identity mode and one per expression. |
| `FaceModel.part(points, part)` | One part as a mesh: `FACE_AND_HEAD`, `TEETH`, `LEFT_EYEBALL` and the others. |
| `MeshField(points, triangles)` | The signed distance to a mesh. |
| `ScannedHead(h, model, hull)` | The scan fitted to one person, over the solids in `hull`. |

`tint_head_skin` writes the face's zones of color into the mesh's `color` attribute. The lips are red. The cheeks, the nose's tip and the ears are a little redder than the forehead. The lids and the skin under the eyes are darker, and the lashes darken the lids' margins. A man's jaw and upper lip carry the gray-blue of a beard under the skin.

`tint_head_skin` also writes a `thinness` attribute. `skin_scatter` reads it, so light behind an ear, a nostril or a lip shows through it, deep red, as three.js's `MeshSSSNodeMaterial` draws it.

## Eyes

`EYES` draws the two eyeballs. Each is a sphere about 24 mm across on the six-foot template, with the cornea proud of it at the front. The lids are a shell round the front of each eyeball, open in an almond-shaped slit. `iris_albedo` maps the pupil, the iris with its fibers and its limbal ring, and the white sclera. `eye_physical` gives the wet cornea a strong clear coat, so the eye catches a glint.

An eyeball goes where its lids go. The face's genes move the lids and the eye's center by different amounts. So `eye_center` takes the center from the ring where the lids rest on the eyeball. No point of the ring lies behind the eyeball, so the eye never stands out in front of its lids.

| Function | Returns |
|---|---|
| `eye_center(dimensions, side)` | The center of one eyeball, in meters. |
| `eye_radius(dimensions)` | Its radius, scaled by stature and `EYE_SIZE`. |
| `eyeball_mesh(dimensions, side, detail)` | Its mesh, with texture coordinates from the front pole. |

`add_head` draws the eyes when `contents` has `EYES`. `ALL` has it. `add_body` draws the eyes and the scalp's hair with the skin.

## Hair

The scalp's hair is strands over a shell. `add_groom` grows the strands. The shell under them is the mass of hair in shade.

The shell lies over the skin itself: about seven millimeters deep at the sides and a centimeter on the crown. It follows every head a genome makes. Its hairline is level across the middle of the forehead, set back at each temple, and turns down past the temples to the sideburns. A male's temples are set back more than a female's. The shell is cut away round each ear and off above the nape.

### Strands

`add_groom(scene, assets, parent, spec, guides, followers)` grows a groom, the way grooming tools grow one:

- Guide strands grow from roots on the shell. Each lies along it, combed away from the crown's whorl and pulled down as the hair grows longer. A guide at the front can fall off the hairline onto the forehead as a fringe. It stops at a ragged line above the brows.
- Follow strands fill in round each guide, as AMD's TressFX makes them. Each keeps an offset from its guide that widens toward the tip.
- Clumping pulls each follower back toward its guide at the tip, so the hair gathers into locks. Frizz moves each tip a little.

Each strand is drawn as a `LineSegments2` a pixel wide, unlit, in colors worked out at its points. A real hair is far thinner than a pixel, so the line stands in for it.

The colors are strand-space shading, as Frostbite's hair works it out. Kajiya and Kay's diffuse and Marschner's specular read the strand's direction, not a normal. Marschner's R highlight reflects white off the fiber; TRT passes through it and comes back in the pigment's color. Light is also lost with depth into the hair, as the Beer-Lambert law has it. Call `HairStrands.shade` when the head turns or the camera moves: the highlights move with them. The shading is ported from Frostbitten Hair WebGPU, and the follow strands from AMD TressFX.

Light that diffuses through a fiber crosses it twice, so the pigment tints the diffuse twice. Pale hair then stays golden and does not wash out to white.

### Hairstyles

A `HairStyle` says how the hair is cut and laid. Pass the same style to `add_groom` as `style` and to `add_head` or `add_body` as `hair_style`.

| Style | The hair |
|---|---|
| `GROWN` | The groom above, combed down to the length `HAIR_LENGTH` asks for. The default. |
| `LAYERED` | Sintel's hair: a layered cut to the jaw, with a fringe. From Sintel Lite by BenDansie, (c) the Blender Foundation, CC-BY 3.0. |
| `MOHAWK` | A crest from the brow to the nape, and shaved sides. From AMD TressFX's Ratboy, MIT license. |

An artist groomed `LAYERED` and `MOHAWK`. `tools/hair_style.py` converts their TressFX files into `assets/hair/`.

A style keeps no head of its own. Each root is a point of a unit cranium, and each strand is kept as offsets from its root in the cranium's frame there. So a style fits every head a genome makes. `HairStyleFile.strand` puts a strand on a person's cranium. The groom then walks its root onto the skin and lifts any point of it that would pass under the skin. The follow strands, the clumping and the shading are the grown hair's.

A mohawk's shell covers only a strip along the midline, so the sides are bare.

`HAIR_CURL` curls the hair of every style. Zero and below is straight. A third is wavy, two thirds curly, and one tightly coiled.

Each guide is sampled at eight points a turn and wound round its own line. It swings across the hair and out off it, never in under it. The swing grows in over the first half turn, so the root stays where it grew. The tighter the curl, the shorter each turn and the fuller the hair stands off the head. See [Genome](Genome).

`HAIR_LENGTH` below zero crops it close. Above zero it grows a fall that hangs over the ears and the nape toward the jaw, open over the face. `hair_albedo` maps its strands. Its mass is the volume of a dome over the cranium times `HAIR_PACKING`, one tenth, for the air between the shafts.

Each eyebrow is an arc on the skin over its orbit, thick at its head and thin at its tail. `BROW_THICKNESS` makes it fuller or finer. `add_head` paints the brows into the skin's colors, hair by hair, in the hair's color. A solid strip stands off the curve of the brow ridge, so the brows are not a mesh. `head_hair` still meshes one, and its mass is its volume.

## Examples

`examples/head.mojo` draws a six-foot male neck and head twice and writes `out/head.png`. The left copy shows the bones, the joint tissues and the muscles. The right copy shows the skin, the hair and the eyes. The program also prints the mass of several head parts.

```bash
.venv/bin/mojo run -I . examples/head.mojo out/head.png
```
