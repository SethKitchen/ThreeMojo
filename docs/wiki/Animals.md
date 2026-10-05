# Animals

`create_animal` draws one animal from a species and a seed. `mesh_animal` poses it and returns a painted mesh.

![Twenty-four procedural animals turn in a grid, and the four-legged ones walk](out/animals.png)

The modules live in `extensions/animals/`. The distance field, the sculpt helpers and the mesher live in `extensions/sdf/`, for any extension. Vectors are the generators' `Vec3d`. The modules port procedural-animals by Majid Manzarpour (MIT, 2026). The original is at https://github.com/majidmanzarpour/threejs-procedural-animals. See [Extensions](Extensions).

## Call it

```mojo
from extensions.animals.build import animal_materials, create_animal, mesh_animal
from extensions.animals.gait import walk_pose
from extensions.animals.options import HIGH, animal_options
from extensions.animals.registry import species_of

var wolf = create_animal(species_of("wolf"), animal_options(3, quality=HIGH))
var still = mesh_animal(wolf, wolf.bind_pose())
var stride = mesh_animal(wolf, walk_pose(wolf.rig, 0.25), workers=0)
```

The geometry has positions, normals and linear vertex colors. Its groups are the surface classes. Draw it with the list from `animal_materials`. Each material reads the vertex colors.

## Species

`SpeciesId` names 24 species, in the order of procedural-animals. `species_of` takes the common name.

| Body plan | Species |
|---|---|
| Paws | bear, cat, cheetah, dog, fox, lion, rabbit, rat, wolf |
| Hooves | boar, cow, deer, goat, horse, pig, sheep |
| Birds | chicken, crow, eagle |
| Swimmers | fish, shark |
| Others | frog, snake, spider |

`species_variants` lists the color morphs of a species. `Variant` picks one by index. `ANY_VARIANT` lets the seed pick it.

## Options

`animal_options` takes a seed, a quality tier, a sex, an age and a morph.

| Field | Type | Default |
|---|---|---|
| `seed` | `Int`, low 32 bits | 1 |
| `quality` | `Quality` | `HIGH` |
| `sex` | `Sex`: `ANY_SEX`, `MALE`, `FEMALE` | `ANY_SEX` |
| `age` | `Age`: `ANY_AGE`, `ADULT`, `JUVENILE` | `ANY_AGE` |
| `variant` | `Variant` | `ANY_VARIANT` |

A seed draws the same individual as procedural-animals draws. The streams are `rng(seed * 2654435761 + 12345)` for the body and `rng(seed * 7919 + 17)` for the coat. The draws come in the original order.

The tier multiplies the species' finest cell size.

| Tier | Factor |
|---|---|
| `HERO` | 1 |
| `HIGH` | 1.3 |
| `MEDIUM` | 2 |
| `LOW` | 3 |
| `CROWD` | 4.2 |

At `MEDIUM` and coarser, thin solids grow to the species' least thickness. Ears and tail tips then stay visible.

## How an animal is built

1. The species draws its traits from the seed: size, proportions and coat values.
2. The species places the joints of its rig and adds the bones.
3. The species sculpts the animal: ellipsoids, round cones, eye lenses and fins, each on a bone.
4. The proportion warps move the sculpt and the joints.
5. A pose turns the bones. Each primitive moves with its bone.
6. Each surface part is meshed by narrow-band surface nets.
7. Each vertex is painted, and its occlusion is baked.

### The distance field

Solids join with a polynomial smooth minimum. Each solid has its own blend radius `k`. A carving solid cuts with the matching smooth maximum. The field is negative inside.

| Kind | Shape |
|---|---|
| `ELLIPSOID` | A turned ellipsoid |
| `CONE` | A round cone between two balls |
| `LENS` | An almond prism: the eye aperture |
| `FIN` | A planar polygon with a thickness and a rounded rim |

### Surface parts

A part is meshed apart from the others. Solids of one part blend. Solids of two parts do not. The lower jaw is its own part, so the mouth can open.

`BODY`, `JAW`, `HORN`, `TEETH`, `TONGUE`, `APPENDAGE`, `HOOF`, `EYEBALL`, `EAR`, `LIMB`, `TAIL` and `WATTLE` are the parts.

### The mesher

`extensions.sdf.mesher.mesh_part` samples the corners of blocks of cells first. It keeps the blocks that the surface can reach. Each kept block is sampled finely with the solids that can change it.

Each cell that the surface crosses gets one vertex. Two Newton steps move the vertex onto the surface. The normal is the field gradient. Each crossed lattice edge makes a quad, split along its shorter diagonal.

Only active blocks hold samples. Memory grows with the surface, not with the box. Work is shared among threads. The mesh is the same for any number of threads.

The mesher uses at most eight sample-and-spill rounds to find all blocks that the surface crosses. If the last round wakes another block, it raises an error. It does not return an incomplete mesh or read samples that do not exist. A surface that finishes on the eighth round is accepted.

The box coordinates must be finite and each upper bound must exceed its lower bound. Each part index must name a primitive in the model. Cell counts, grid products and storage byte counts must fit in `Int`. The mesher checks these limits before the related allocation. These checks do not add a smaller fixed grid limit.

### The coat

A painter reads one vertex at a time. It gets the tag and the bone of the nearest solid. It gets the position and normal in the reference bind pose. A mark therefore stays on the skin when the animal moves. The painter returns a linear color and a `SurfaceClass`.

| Class | Material |
|---|---|
| `FUR`, `FEATHER` | Lambert, matte |
| `SKIN` | Phong, soft sheen |
| `NOSE`, `WET` | Phong, tight highlight |
| `KERATIN`, `SCALES`, `CHITIN` | Phong, gloss |
| `EYE` | Phong, the tightest highlight |

Near a joint, the colors of the two bones blend over the blend radius of their solids.

## Pose and walk

`Pose` turns bones about their head joints. A child bone rides its parent. `Pose.root` moves the whole animal.

`walk_pose` gives an in-place lateral-sequence walk. Dynamic similarity supplies a reference stride at a Froude number, 0.25 by default. `walk_stride` caps that stride to the common reach of all four two-link legs. The visual stride can therefore be shorter than the reference. See [Animal anatomy](Animal-anatomy#gait-timing).

Each foot is in stance for 70 % of the cycle. Two-bone inverse kinematics keep a stance foot at its bind height while it moves backward under the body. All four feet use the same bounded sweep. The leg targets compensate for the body bob. The tail swings once. A rig without four legs gets its bind pose.

`walk_pose_at` takes a `Duration`. It samples the phase from that animal's reference frequency. Use the same time for animals in one scene. The anatomy gallery plays one shared-time clip once, because the species have different cycle periods.

This is a kinematic illustration. The reference frequency and stride relation are estimates. The walk does not translate the body or solve contact dynamics. If a caller translates the body, the speed consistent with the visual stance is `walk_stride * stride_frequency`, not the uncapped reference speed. Validated engineering locomotion is not supported.

## Differences from procedural-animals

These changes improve the result in the software renderer.

- A pose moves the solids and meshes the field again. The original skins one mesh with dual quaternions. A skinned joint loses volume as it bends. A re-meshed joint keeps its volume and its blend.
- The proportion warps move the sculpt, not the mesh. The surface stays a true field surface with exact normals.
- Occlusion is baked from the field into the vertex colors. Each vertex samples the field five times along its normal. Creases such as the armpit and the eye socket get darker.
- Fur and feathers tilt their normals by fractal noise in the bind pose. The noise is stretched along the body. Lambert shading then shows combed clumps on the coat.
- Each eyeball is a separate part with a finer cell. It is painted with a pupil, an iris with radial fibers, a limbal ring and a sclera. A slit or bar pupil is drawn where the species has one.
- The mesher stores only its active blocks, so a fine cell costs little memory.

## What is not ported

- The fur, feather and scale shells, and the shader that draws them. The coat is in the vertex colors.
- Feather cards and whiskers. Wings and tails are sculpted as fins.
- The behavior, action and steering engines. `walk_pose` is one gait.
- Web workers and baked `.animal` files. A build runs on threads.
- Dual-quaternion skinning. Poses re-mesh instead.

## Anatomy

Each animal also has a skeleton, Hill-type muscles, segment mass and inertia, and an engineering mode. See [Animal anatomy](Animal-anatomy).

## Types and checks

Each id, kind and mode is a type with `is_valid`: `SpeciesId`, `PrimitiveKind`, `BoneId`, `TagId`, `SurfacePart`, `SurfaceClass`, `WarpKind`, `Quality`, `Sex`, `Age` and `Variant`. `create_animal`, `check_options`, `require_species`, `require_part` and `require_kind` refuse a value that is not valid. The files in `tests/compile_fail/` prove that a bare integer does not compile.
