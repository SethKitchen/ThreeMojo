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
4. It cuts the shell at its hems, and where a layer over it covers it.

A drape pass moves each covered vertex halfway to the mean of its neighbors. Then it pushes the vertex back out to its standoff. One pass keeps the skin's shape under a thin cloth. Twenty-four passes span the hollows, as a stiff plate does.

A layer under a garment lifts it in full inside and at that layer's hem. The lift fades out a quarter of a cover value past the hem. So a tunic rises smoothly over the top of a hose. No layer can pass through the layer under it at rest.

A garment is cut where a layer over it covers it past 0.75. That layer's hem lies at 0.5, so the garment ends under it. The cut runs along the iso-line, as a hem does, and not along the edges of triangles. So no whole triangle of an inner layer reaches out past the hem of the layer over it.

The hands' skins are meshes of their own, and each layer stands off only the layers under it on the same skin. So at the wrist a glove on the hand's skin can still show past a vambrace on the arm's.

A shell is one face of its fabric, so a hem has no thickness of its own. `add_rim` gives each open edge a rim: a strip of two triangles from the edge in along the normals, facing out of the edge. `dress` rims each fabric 1.5 mm thick or more, at its own thickness and at most 6 mm deep. So the hems of leather, padding, mail and plate, and the edge of each lame, show their thickness and catch the light. Copies of a vertex at one position are one vertex, so a seam where the skin was parted takes no rim.

The skin drops each triangle whose every corner has a cover value of 0.75 or more from a garment. So skin cannot show through a garment when the body bends, and a dressed person costs about as many triangles as a bare one.

## Forms

A shell made from the skin follows each thigh and each toe. A skirt and a boot do not. The form says how the shell is shaped there.

| Form | The shell | Example |
|---|---|---|
| `FITTED` | follows the skin everywhere | a shirt, hose, a coif |
| `SKIRTED` | hangs below the hips as one tube round both legs | a tunic, a hauberk, a surcoat, a fauld |
| `SHOD` | closes each foot in a smooth last | boots, sabatons |
| `COWLED` | closes the head in a loose cowl, open at the face | a hood |
| `BANDED` | is drawn as a taut band round the body, level at its top and its bottom | a belt |
| `HATTED` | is drawn as the hat or the helmet its headwear names, round the head | a great helm, a crown, a wizard's hat |
| `DOMED` | closes each shoulder in one smooth dome that stands well off it | great pauldrons |

A garment cut from the skin has as many triangles as the skin under it. A skirt's rings and a hat's rings and sectors do not. On a coarse skin they would keep their full count and draw more triangles than the body. So `dress` gives them a share of their full detail, as `garment_detail` reads it off the skin:

- A skin of 10,000 triangles or more takes the full detail: the body's share of a 16,000-triangle budget.
- A coarser skin takes less, as the square root of its triangles over 10,000, and one half at the least.
- A skirt's rings then lie farther apart, 6 cm at one half. A hat keeps fewer sectors and rings: 24 sectors and 12 rings at one half.

At a 4,000-triangle budget, a robe draws 7,900 triangles, not 11,200, and a straw hat 2,900, not 5,400.

### Bands

A belt is narrower than the ramp a hem is cut across. So its cover stays near one half, and a cut along it came out ragged on a game's coarse skin. `extensions/attire/band.mojo` draws a `BANDED` garment as a lined band of leather 4 cm deep on the template.

1. The band's middle is the mean height of the piece the garment's cover cuts.
2. The garment's whole shell is sliced at three rows across the band, with the arms left out. Each slice is closed as a convex hull, so the band spans the hollow of the back, as a belt drawn taut does.
3. Each side of each row stands on the hull, and takes the skin weights of the shell vertex nearest it.

A band hides nothing under it: the tunic under a belt is drawn whole.

### Skirts

`extensions/attire/skirt.mojo` hangs a skirt in four steps.

1. `skirt_top` is 3 cm below the hip joints on the template, above the crotch. There the shell is one tube round the pelvis. The shell of the trunk and the legs is cut there.
2. `skirt_envelope` slices the garment's own shell at rings 3 cm apart, from the top to the lowest point of the shell on the legs. That point is the hem. Each slice is closed as a convex hull, so it spans the gap between the thighs.
3. Each ring is at least as wide as the ring above it, plus the flare times the drop. So the cloth falls straight or flares, and does not tuck in between the legs. A skirt under it lifts it by that skirt's thickness and this garment's clearance. So does metal on the legs under it, such as plate legs, which stands off the thighs.
4. `skirt_mesh` lofts the rings on 40 sides. The top ring reaches 1.5 cm up inside the shell, so no gap opens at the cut.

Ten folds run down each skirt. They stand only out of the rings, so no fold dips into a skirt under it. They deepen as the cloth falls, from none at the top to their whole depth at the hem. Every skirt's folds lie at the same sides, so a skirt over another folds over its folds. `fold_depth` gives the depth at the hem.

| Fabric | Fold at the hem |
|---|---|
| `LINEN`, `SILK` | 18 mm |
| `WOOL`, `VELVET` | 25 mm |
| `LEATHER`, `MAIL`, `SCALE` | 6 mm |
| `PADDING`, `STRAW` | 4 mm |
| `FUR`, `FELT` | 10 mm |
| `PLATE` | none |

A drawn skirt is lined: it has an inner face one fabric thickness inside, and a strip across its hem. So the hem shows its thickness, and the inside of the skirt draws when it is seen from below.

Each vertex at the top takes the weights of the nearest vertex of the shell. Down the skirt the weights pass to the thighs: at the hem the thighs hold 0.9 of each vertex. The right thigh turns the right side and the left thigh the left side. The two share a band 10 cm wide at the middle of the front and the back. So the skirt opens as a leg lifts.

The cover value falls from one to one half over the 4 cm above the hem. So a trim lies along a skirt's hem, as along any hem.

Below the top, a skirt hangs clear of the legs. So it hides neither the skin nor the garments under it there, and the hose and the legs draw under it. A band 6 cm deep below the top stays hidden, so no triangle that crosses the top shows through the shell over it. A skirt over another that falls as far hides it. The inner skirt is then not drawn.

### Lasts

`extensions/attire/last.mojo` shoes each foot in four steps.

1. `last_top` is 2 cm above the higher ankle joint on the template. The shell is cut 2 cm below that, so its edge lies inside the last.
2. `foot_lasts` closes the shell's vertices below the top on each side of the hips in their convex hull. The hull also takes the points where the shell crosses the top. So the hull reaches up to the top, even on a coarse skin.
3. `last_mesh` casts a sphere of 12 rings and 18 sectors from the middle of the foot onto the hull. The sphere is stretched to the foot's box. So the last is evenly meshed, even where the hull has long flat facets over the toes and the arch. The last stands 1.5 mm out of the hull. So the seam where the shaft meets it is a clean step, as a boot's welt is.
4. The flat top of the hull lies inside the shaft. The last is cut level 3 mm below it.

Each vertex of a last takes the weights of the nearest vertex of the shell. So the toe box bends with the toes. An outer last hides the last under it: sabatons over boots draw the boots' shafts and not their lasts.

### Cowls

`extensions/attire/cowl.mojo` closes a hood round the head in four steps.

1. `cowl_bottom` is at the base of the neck. The shell is cut 1.5 cm above it, so its edge lies inside the cowl.
2. `head_cowl` closes the shell's vertices above the bottom in their convex hull. The hull also takes the points where the shell crosses the bottom, so it reaches down to the bottom. The hull spans the ears, the nape and the hollow under the chin.
3. `cowl_mesh` casts a sphere of 18 rings and 28 sectors onto the hull, 6 mm out of it, so the hood stands loose. The sphere's pole looks forward through the face, so its rings run round the face's opening.
4. The cowl is cut open along the face's oval and level at its bottom. A lining one fabric thickness inside it shows where the opening looks into the hood.

`face_oval` gives the oval's distance without the clamp of `face_opening`. So the cut runs smoothly through triangles larger than the opening's ramp.

### Domes

A pauldron made from the skin follows the shoulder's muscles, and reads as a sleeve. `extensions/attire/dome.mojo` closes each shoulder of a `DOMED` garment in one dome, as a heroic harness's pauldrons are.

1. The shell is split at the middle of the chest into each shoulder's part.
2. Each part's vertices are closed in their convex hull.
3. A sphere of 16 rings and 24 sectors, stretched to the part's box, is cast from the hull's middle. It stands 2.2 cm out of the hull.
4. The dome is cut where it turns in toward the body, past a third of its half width from its middle, and under the armpit. The band along that edge takes the trim.
5. A lining a fabric's thickness inside it shows under its edge.

Each vertex takes the skin weights of the nearest vertex of the shell. So a lamed dome rides the chest at its top and opens as the arm rises. A dome hides none of the skin or the garments under it.

### Hats and helmets

A garment made from the skin follows the face and the ears. A hat stands on the head, over the hair. `extensions/attire/headwear.mojo` draws a `HATTED` garment as the hat or the helmet its `headwear` names.

1. The shell's vertices above the base of the neck are closed in their convex hull, as a cowl's are.
2. `HeadFrame` reads the hull: its middle, its top, and its width at each height and each way round. A hat's band lies 10 cm below the top of the head, just over the brows. It stands 1.2 cm out of the hull, so it sits over the hair.
3. The hat is built round the band, scaled to the stature.

| Headwear | Shape |
|---|---|
| `GREAT_HELM` | the hull, cast out of its middle 1.6 cm off it, down to the base of the neck; a flat top, a ridge down the front, and an eye slit on each side of it |
| `HALF_HELM` | the same cast, 1.2 cm off the hull, cut level just over the brows, with a nasal and a ridge over the crown |
| `HORNED_HELM` | a half helm with a horn on each side that curves out, up and forward |
| `WIZARD_HAT` | a brim 8.5 cm wide that droops at its edge, and a cone 30 cm tall whose tip bends back and down |
| `STRAW_HAT` | a brim 9.5 cm wide that turns up at its edge, and a round crown 2.5 cm over the head |
| `FEATHERED_CAP` | a crown that rises 4 cm over the head to a point over the brow, a brim that turns up behind, and a feather |
| `CROWN` | a band 4 cm deep that flares a little, with eight points, a stone at the foot of each and a larger one in front |
| `CIRCLET` | a band 1.2 cm deep that dips to a point over the brow, with a stone there |

Each hat has an inner face a fabric's thickness in, so it shows from below. A crown of a hat stands clear of the head under it at every height. Its band, rims and ridges take the trim dye. Its stones, horns and feather take the accent dye: their `accent` attribute is one. A hat rides the head, and hides none of the face under it.

`examples/headwear.mojo` draws each hat and helmet on a head of its own, and writes `out/headwear.png`.

![Eight busts, each in one of the eight hats and helmets](out/headwear.png)

A great helm hides the hair. Every other hat keeps it: `press_hair` draws each point of the strands and cards over the band in under the hat. A hat that closes over the head cuts the hair's shell away over its band. The shell can stand out of the hat over the ears. A crown and a circlet are open over the hair, so they keep the shell whole.

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
| `FUR` | 1.4 kg/m² | 12 mm | 6 | matte, with a broad sheen |
| `FELT` | 600 g/m² | 3 mm | 4 | matte, with a faint sheen |
| `STRAW` | 350 g/m² | 2 mm | 6 | dull, with a faint clear coat |
| `SCALE` | 10.5 kg/m² | 4 mm | 4 | its metal, a little rougher than plate |

`ArealDensity` is a `Quantity[-2, 1, 0, 0]`, in `extensions/attire/quantities.mojo`. Its units are `KILOGRAM_PER_SQUARE_METER`, `GRAM_PER_SQUARE_METER` and `OUNCE_PER_SQUARE_YARD`. A metal shows what it reflects, so give the scene an environment.

### Metals

Mail and plate are made of a `Metal`. A garment's `metal` is steel unless it names another. The metal sets the look: plate takes the metal's roughness and metalness, and mail is a quarter rougher, because its rings scatter the light. The code is in `extensions/attire/metal.mojo`.

| Metal | Color | Roughness | Metalness |
|---|---|---|---|
| `IRON` | dark gray | 0.5 | 0.9 |
| `STEEL` | bright gray | 0.3 | 0.9 |
| `BLACKENED` | near black | 0.55 | 0.7 |
| `BLUED` | deep blue | 0.28 | 0.9 |
| `BRONZE` | brown gold | 0.35 | 0.9 |
| `COPPER` | red brown | 0.35 | 0.9 |
| `BRASS` | pale gold | 0.3 | 0.9 |
| `SILVER` | white | 0.18 | 0.95 |
| `GOLD` | deep yellow | 0.2 | 0.95 |

`forged(garment, metal, trim)` makes a mail or plate garment of a metal. Its primary and secondary dyes take the metal's color. Its trim takes the color of the trim's metal, or of its own metal when no trim is given. Its accent dye is left for stones and horns. `forged` refuses cloth.

```mojo
var helm = forged(bascinet(), BLUED, GOLD)
```

## Surface

`dress` gives each garment texture coordinates in meters, round its bones. Mail, padding and cloth then take a bump map that tiles at its true size.

| Fabric | Bump map | Tile | Scale |
|---|---|---|---|
| `MAIL` | riveted rings, four in one | 4 cm | 0.6 |
| `PADDING` | diamond quilting | 6 cm | 1.0 |
| `LINEN`, `WOOL`, `SILK`, `VELVET` | two-over-two twill | 4 mm | 0.15 |
| `FUR` | locks that fall down the garment | 3 cm | 1.6 |
| `STRAW` | flat straws plaited over and under | 1.2 cm | 0.5 |
| `LEATHER` | pebbled grain, rounded cells parted by creases | 1.2 cm | 0.35 |
| `SCALE` | rounded scales, each rising to its lower edge over the row below | 5 cm, two scales across | 1.2 |
| `PLATE`, `FELT` | none | | |

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
| `CHEVRON` | the field | a band like an inverted V, its point on the chest |
| `CROSS` | the field | an upright cross, crossed on the chest |
| `SALTIRE` | the field | a diagonal cross, crossed on the chest |
| `BEND` | the field | a band from the right shoulder to the left hip |
| `PALY` | even upright bands | odd upright bands |
| `CHECKY` | even squares | odd squares |

A charge lies on the front and the back alike, as a tabard's does. Each band of a cross, a saltire, a chevron or a bend is 11 cm wide on the template. A pattern is a field over the body whose sign says the dye, so each charge has a crisp edge.

`examples/heraldry.mojo` dresses ten men in surcoats, one in each pattern, and writes `out/heraldry.png`.

![Ten men in surcoats, one in each of the ten dye patterns](out/heraldry.png)

Every pattern puts the trim dye along each hem. `dye_pattern` cuts the garment along each boundary, so a boundary is a crisp line. A vertex whose `accent` attribute is one half or more takes the accent dye: a hat's stones, horns and feather. Each vertex keeps its channel weights in a `dye` attribute.

Wear is four more channels in a `wear` attribute: dirt, blood, wet and damage. `soil` lays dirt from the lowest point up. `stain` lays any channel round a point. `paint` mixes the dyes, then the wear, into the `color` attribute.

```mojo
stain(piece, BLOOD, Vector3(0.1, 1.2, 0.15), Length(0.08, METER), 0.9)
soil(piece, Length(0.3, METER), 0.6)
paint(piece, garment.dyes)
```

## The wardrobe

`wardrobe()` gives twenty-four medieval garments.

| Garment | Slot | Layer | Fabric | Form |
|---|---|---|---|---|
| `shirt` | torso | under | linen | fitted |
| `hose` | legs | under | wool | fitted |
| `tunic` | torso | mid | wool | skirted, flare 0.25 |
| `gambeson` | torso | mid | padding | skirted, flare 0.1 |
| `hauberk` | torso | outer | mail, brass at the hems | skirted, flare 0.15 |
| `coif` | head | outer | mail | fitted |
| `hood` | head | over | wool | cowled |
| `boots` | feet | outer | leather | shod |
| `gloves` | hands | outer | leather | fitted |
| `cuirass` | torso | armor | plate | fitted |
| `fauld` | waist | armor | plate | skirted, flare 0.12 |
| `pauldrons` | shoulders | armor | plate | fitted |
| `vambraces` | arms | armor | plate | fitted |
| `greaves` | legs | armor | plate | fitted |
| `bascinet` | head | armor | plate | fitted |
| `surcoat` | torso | over | linen, per pale | skirted, flare 0.3 |
| `breeches` | legs | mid | wool, cut loose | fitted |
| `gown` | torso | mid | wool, to the ankles | skirted, flare 0.32 |
| `robe` | torso | mid | wool, to the ankles, cut loose | skirted, flare 0.12 |
| `jerkin` | torso | outer | leather, sleeveless | skirted, flare 0.15 |
| `belt` | waist | over | leather | banded |
| `gorget` | neck | armor | plate, rigid on the chest | fitted |
| `gauntlets` | hands | armor | plate, rigid on each hand | fitted |
| `sabatons` | feet | armor | plate, rigid on each foot and its toes | shod |

### The armory

`armory()` in `extensions/attire/armory.mojo` gives more armor and three helmets. Each piece of plate replaces the wardrobe's piece in its slot and layer. Plate legs replace greaves, a platebody a cuirass, and a plate skirt a fauld.

| Garment | Slot | Layer | Fabric | Articulation | Form |
|---|---|---|---|---|---|
| `platebody` | torso | armor | plate | five lames from the chest | fitted |
| `plate_legs` | legs | armor | plate | rigid on each thigh and shin | fitted |
| `plate_skirt` | waist | armor | plate | six lames from the hips | skirted, flare 0.18 |
| `arm_harness` | arms | armor | plate | rigid on each upper arm and forearm | fitted |
| `great_pauldrons` | shoulders | armor | plate | four lames from the chest | domed |
| `chain_shirt` | torso | outer | mail, short sleeves | flexible | skirted, flare 0.1 |
| `scale_shirt` | torso | armor | scale, short sleeves | flexible | skirted, flare 0.12 |
| `mail_chausses` | legs | outer | mail | flexible | fitted |
| `bracers` | arms | outer | leather | flexible | fitted |
| `great_helm` | head | armor | plate, brass trim | rigid on the head | hatted |
| `half_helm` | head | armor | plate | rigid on the head | hatted |
| `horned_helm` | head | armor | plate, ivory horns | rigid on the head | hatted |

### The apparel

`apparel()` in `extensions/attire/apparel.mojo` gives work clothes, furs, robes, boots and five hats.

| Garment | Slot | Layer | Fabric | Form |
|---|---|---|---|---|
| `smock` | torso | mid | linen, cut loose, to mid-thigh | skirted, flare 0.3 |
| `bodice` | torso | outer | velvet, over a gown | fitted |
| `trousers` | legs | mid | wool, cut loose, to the ankle | fitted |
| `fur_kilt` | waist | outer | fur, to above the knee | skirted, flare 0.25 |
| `fur_mantle` | shoulders | over | fur | fitted |
| `royal_mantle` | shoulders | over | velvet, edged in white fur | fitted |
| `wizard_robe` | torso | mid | wool, cut loose, to the floor | skirted, flare 0.35 |
| `cassock` | torso | mid | wool, a high collar, to the ankles | skirted, flare 0.2 |
| `tall_boots` | feet | outer | leather, to the knee | shod |
| `fur_boots` | feet | outer | fur, to mid-shin | shod |
| `sash` | waist | over | silk | banded |
| `wizard_hat` | head | over | felt | hatted |
| `straw_hat` | head | over | straw | hatted |
| `feathered_cap` | head | over | felt, a red feather | hatted |
| `crown` | head | over | gold plate, rubies | hatted |
| `circlet` | head | over | silver plate, a sapphire | hatted |

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

`tests/test_attire_kinds.mojo`, `test_attire_fabric.mojo`, `test_attire_metal.mojo`, `test_attire_mesh_ops.mojo`, `test_attire_cover.mojo`, `test_attire_shell.mojo`, `test_attire_skirt.mojo`, `test_attire_last.mojo`, `test_attire_cowl.mojo`, `test_attire_dome.mojo`, `test_attire_headwear.mojo`, `test_attire_surface.mojo`, `test_attire_dye.mojo`, `test_attire_garment.mojo`, `test_attire_armory.mojo` and `test_attire_binding.mojo` cover this page. Each kind type has a file in `tests/compile_fail/`.
