# Garments

A garment is the covered part of a person's skin, moved out along the skin's normals and cut at clean hems. It follows any genome and stature, takes the skin's weights, and stands off every layer under it. See [Outfits and armor](Outfits-and-armor) to dress a person.

```mojo
from extensions.attire.garment import gambeson, hauberk
from extensions.attire.outfit import Outfit, dress

var outfit = Outfit()
outfit.add(gambeson())
outfit.add(hauberk())
var dressed = dress(scene, assets, person, outfit)
```

This is not a three.js port. The code is in `extensions/attire/`.

## What a garment holds

A `Garment` holds no mesh. `dress` makes its mesh from the skin of the person who wears it.

| Field | Type | Meaning |
|---|---|---|
| `slot` | `Slot` | Where it goes: head, neck, shoulders, torso, arms, hands, waist, legs, feet or back. |
| `layer` | `Layer` | How far from the skin it sits: under, mid, outer, armor or over. |
| `fabric` | `FabricKind` | What it is made of. |
| `cover` | `Cover` | What it covers, joint by joint. |
| `articulation` | `Articulation` | How it follows the bones: flexible, rigid or lamed. |
| `anchor`, `lames` | `Joint`, `Int` | The bone a plate rides, and the number of lames. |
| `pattern`, `dyes` | `DyePattern`, four `Color` values | How it is dyed. |
| `drape`, `ease` | `Int`, `Length` | Smoothing passes of its shell, and how loose it is cut. |
| `form`, `flare` | `Form`, `Float32` | How its shell is shaped where it does not follow the skin, and how far a skirt widens for each meter it falls. |

Every slot, layer, fabric, articulation, pattern, form, dye channel and wear channel is a type with `is_valid`. A bare integer does not compile.

## Cover

A `Cover` gives each joint of the rig a span along its bone, from a start to an end. Each is a fraction of the bone's length from the joint.

| Span | Meaning |
|---|---|
| `reach_to(joint)` | All of the joint's skin, past both ends of the bone. |
| `reach_to(joint, 0.9)` | From the joint to 0.9 of the bone. A long sleeve reaches 0.9 of the forearm. |
| `reach_to(joint, 1, start=0.45)` | From 0.45 of the bone to its end and past it. A boot covers the shin from 0.45 down. |

The cover value of a skin vertex is the sum of its skin weights, each times its joint's coverage there. A span's end ramps linearly over 8 cm along the bone. The values are then smoothed over three passes. The garment is cut where the value is one half. So a hem runs as a clean curve round the limb, not along the edges of triangles.

`face_open` leaves an oval opening in front of the face in the head and the neck. A coif, a hood and a bascinet use it.

## The shell

`dress` makes each garment in four steps.

1. It reads the skin once: positions, normals and the vertices that share one position.
2. It computes the standoff of each vertex: the garment's clearance and ease, past the outer face of each layer under it.
3. It moves each vertex out by its standoff and drapes the shell.
4. It drops what a layer over it hides, and cuts the shell at its hems.

A drape pass moves each covered vertex halfway to the mean of its neighbors. Then it pushes the vertex back out to its standoff. One pass keeps the skin's shape under a thin cloth. Twenty-four passes span the hollows, as a stiff plate does.

A layer under a garment lifts it in full inside and at that layer's hem. The lift fades out a quarter of a cover value past the hem. So a tunic rises smoothly over the top of a hose. No layer can pass through the layer under it at rest.

A triangle is hidden when every corner has a cover value of 0.75 or more from a layer over it. The skin and the inner layers drop these triangles. So skin cannot show through a garment when the body bends, and a dressed person costs about as many triangles as a bare one.

## Forms

A shell made from the skin follows each thigh and each toe. A skirt and a boot do not. The form says how the shell is shaped there.

| Form | The shell | Example |
|---|---|---|
| `FITTED` | follows the skin everywhere | a shirt, hose, a coif |
| `SKIRTED` | hangs below the hips as one tube round both legs | a tunic, a hauberk, a surcoat, a fauld |
| `SHOD` | closes each foot in a smooth last | boots |

### Skirts

`extensions/attire/skirt.mojo` hangs a skirt in four steps.

1. `skirt_top` is 3 cm below the hip joints on the template, above the crotch. There the shell is one tube round the pelvis. The shell of the trunk and the legs is cut there.
2. `skirt_envelope` slices the garment's own shell at rings 3 cm apart, from the top to the lowest point of the shell on the legs. That point is the hem. Each slice is closed as a convex hull, so it spans the gap between the thighs.
3. Each ring is at least as wide as the ring above it, plus the flare times the drop. So the cloth falls straight or flares, and does not tuck in between the legs. A skirt under it lifts it by that skirt's thickness and this garment's clearance.
4. `skirt_mesh` lofts the rings on 40 sides. The top ring reaches 1.5 cm up inside the shell, so no gap opens at the cut.

A drawn skirt is lined: it has an inner face one fabric thickness inside, and a strip across its hem. So the hem shows its thickness, and the inside of the skirt draws when it is seen from below.

Each vertex at the top takes the weights of the nearest vertex of the shell. Down the skirt the weights pass to the thighs: at the hem the thighs hold 0.9 of each vertex. The right thigh turns the right side and the left thigh the left side. The two share a band 10 cm wide at the middle of the front and the back. So the skirt opens as a leg lifts.

The cover value falls from one to one half over the 4 cm above the hem. So a trim lies along a skirt's hem, as along any hem.

Below the top, a skirt hangs clear of the legs. So it hides neither the skin nor the garments under it there, and the hose and the legs draw under it. A band 6 cm deep below the top stays hidden, so no triangle that crosses the top shows through the shell over it. A skirt over another that falls as far hides it. The inner skirt is then not drawn.

### Lasts

`extensions/attire/last.mojo` shoes each foot in four steps.

1. `last_top` is 2 cm above the higher ankle joint on the template. The shell is cut 2 cm below that, so its edge lies inside the last.
2. `foot_lasts` closes the shell's vertices below the top on each side of the hips in their convex hull.
3. `last_mesh` casts a sphere of 12 rings and 18 sectors from the middle of the foot onto the hull. The sphere is stretched to the foot's box. So the last is evenly meshed, even where the hull has long flat facets over the toes and the arch. The last stands 1.5 mm out of the hull. So the seam where the shaft meets it is a clean step, as a boot's welt is.
4. The flat top of the hull lies inside the shaft. The last is cut level 3 mm below it.

Each vertex of a last takes the weights of the nearest vertex of the shell. So the toe box bends with the toes.

## Fabrics

`fabric(kind)` gives the constants of a fabric. `fabric_material(kind, tint)` gives its physically based look, with vertex colors on and the scene's environment reflected.

| Kind | Areal density | Thickness | Drape | Look |
|---|---|---|---|---|
| `LINEN` | 200 g/m² | 0.5 mm | 1 | sheen |
| `WOOL` | 300 g/m² | 1.2 mm | 2 | sheen |
| `SILK` | 80 g/m² | 0.2 mm | 1 | bright sheen |
| `VELVET` | 350 g/m² | 1.5 mm | 2 | colored sheen |
| `LEATHER` | 1.7 kg/m² | 2 mm | 3 | faint clear coat |
| `PADDING` | 2.4 kg/m² | 15 mm | 6 | sheen |
| `MAIL` | 8.5 kg/m² | 3 mm | 3 | rough metal |
| `PLATE` | 15.7 kg/m² | 2 mm | 24 | polished metal under a clear coat |

`ArealDensity` is a `Quantity[-2, 1, 0, 0]`, in `extensions/attire/quantities.mojo`. Its units are `KILOGRAM_PER_SQUARE_METER`, `GRAM_PER_SQUARE_METER` and `OUNCE_PER_SQUARE_YARD`. A metal shows what it reflects, so give the scene an environment.

## Surface

`dress` gives each garment texture coordinates in meters, round its bones. Mail, padding and cloth then take a bump map that tiles at its true size.

| Fabric | Bump map | Tile | Scale |
|---|---|---|---|
| `MAIL` | riveted rings, four in one | 4 cm | 0.6 |
| `PADDING` | diamond quilting | 6 cm | 1.0 |
| `LINEN`, `WOOL`, `SILK`, `VELVET` | two-over-two twill | 4 mm | 0.15 |
| `LEATHER`, `PLATE` | none | | |

`garment_uvs(piece, rig)` makes the coordinates in three steps.

1. It cuts the garment into one part for each chain of bones. A chain is a run of bones that bend less than about 45 degrees from each other, such as the upper arm and the forearm. A part is where its chain holds at least half of the skin's weight. The rest follows the chain that holds most of it.
2. It cuts each part along a seam down the back of its bones.
3. It sets `u` to the arc round the bone, at the chain's mean radius. It sets `v` to the distance down the chain.

So `v` runs on across the elbow and the knee, and no triangle mixes two chains. A pattern meets itself at the back seams and where a sleeve meets the body, as the panels of a sewn garment do.

`SurfaceMaps` makes each bump map once and gives it to every material that needs it. Each map is a 64-texel height image with a mip chain. In a full-body view a ring of mail is smaller than a pixel, and the mip chain turns the rings into a fine glint.

## Dyes and wear

A garment has four dye channels: primary, secondary, trim and accent. A pattern says where each lies.

| Pattern | Primary | Secondary |
|---|---|---|
| `SOLID` | everywhere | nowhere |
| `PARTY` | the wearer's right side | the left side |
| `STRIPES` | even bands round the body | odd bands |
| `QUARTERLY` | upper right and lower left | upper left and lower right |

Every pattern puts the trim dye along each hem. `dye_pattern` cuts the garment along each boundary, so a boundary is a crisp line. Each vertex keeps its channel weights in a `dye` attribute.

Wear is four more channels in a `wear` attribute: dirt, blood, wet and damage. `soil` lays dirt from the lowest point up. `stain` lays any channel round a point. `paint` mixes the dyes, then the wear, into the `color` attribute.

```mojo
stain(piece, BLOOD, Vector3(0.1, 1.2, 0.15), Length(0.08, METER), 0.9)
soil(piece, Length(0.3, METER), 0.6)
paint(piece, garment.dyes)
```

## The wardrobe

`wardrobe()` gives sixteen medieval garments, from the skin out.

| Garment | Slot | Layer | Fabric | Form |
|---|---|---|---|---|
| `shirt` | torso | under | linen | fitted |
| `hose` | legs | under | wool | fitted |
| `tunic` | torso | mid | wool | skirted, flare 0.25 |
| `gambeson` | torso | mid | padding | skirted, flare 0.1 |
| `hauberk` | torso | outer | mail, brass at the hems | skirted, flare 0.15 |
| `coif` | head | outer | mail | fitted |
| `hood` | head | over | wool | fitted |
| `boots` | feet | outer | leather | shod |
| `gloves` | hands | outer | leather | fitted |
| `cuirass` | torso | armor | plate | fitted |
| `fauld` | waist | armor | plate | skirted, flare 0.12 |
| `pauldrons` | shoulders | armor | plate | fitted |
| `vambraces` | arms | armor | plate | fitted |
| `greaves` | legs | armor | plate | fitted |
| `bascinet` | head | armor | plate | fitted |
| `surcoat` | torso | over | linen, per pale | skirted, flare 0.3 |

## Garments made elsewhere

An artist can model a garment on one body and export it to glTF. `bind_garment` reads where each vertex lies against that body's skin. It stores the joint that weighs most there and where the skin point stands from that joint, in statures. It also stores how far the vertex stands off the skin.

`fit_garment` puts the garment on another body. It goes to the same place from the same joint of the new rig, and finds the nearest point of the new skin. It stands the vertex off that point by the same distance. It never reads the old skin's topology. `wear_fitted` adds the result as a skinned mesh.

```mojo
var binding = bind_garment(coat, maker_skin, maker.rig)
var fitted = fit_garment(binding, coat, wearer_skin, wearer.rig)
_ = wear_fitted(scene, assets, wearer, fitted^, look)
```

## Why the shell comes from the skin

The plan first made each shell from the body's distance field. The skin is a better source, for three reasons. The garment shares the skin's vertices until it is cut, so it takes the skin's weights exactly. Hiding the skin under a garment is a test per vertex, with no search. And a shell costs one pass over the skin, so a test dresses a person in well under a second.

Roblox's cages and MakeHuman's `mhclo` files bind a garment to a body mesh from outside. Kingdom Come: Deliverance pushes each layer out of the one under it with ray casts. Here each layer stands off the layer under it vertex by vertex, because every layer has the same vertices.

## Tests

`tests/test_attire_kinds.mojo`, `test_attire_fabric.mojo`, `test_attire_mesh_ops.mojo`, `test_attire_cover.mojo`, `test_attire_shell.mojo`, `test_attire_skirt.mojo`, `test_attire_last.mojo`, `test_attire_surface.mojo`, `test_attire_dye.mojo`, `test_attire_garment.mojo` and `test_attire_binding.mojo` cover this page. Each kind type has a file in `tests/compile_fail/`.
