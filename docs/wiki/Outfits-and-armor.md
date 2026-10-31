# Outfits and armor

An outfit is the list of garments one person wears. `dress` makes every garment from that person's skin and adds it to the scene on the person's own skeleton. Plate rides one bone or bends in lames. Sockets hang shields and swords from the body.

![A peasant, a man-at-arms and a knight in plate walk while the camera turns](out/armory.png)

```mojo
from extensions.attire.outfit import dress
from extensions.attire.preset import outfit_named

var person = add_game_humanoid(scene, assets, root, spec, 24000)
var dressed = dress(scene, assets, person, outfit_named("knight"))
```

This is not a three.js port. The code is in `extensions/attire/`. See [Garments](Garments) for one garment, [Cloth and spring bones](Cloth-and-spring-bones) for motion, and [Attire estimates](Attire-estimates) for mass and protection.

## Outfits

`Outfit.add` refuses a second garment in the same slot and layer. A person wears one tunic, over one shirt. `Outfit.order` gives the garments from the skin out: by layer, then in the order they were added.

`dress(scene, assets, person, outfit)` does five things.

1. It makes each garment's shell from each of the person's skinned meshes: the body and both hands. It hangs a skirted garment's skirt and closes a shod garment's feet in lasts. See [Forms](Garments#forms).
2. It drops the skin triangles the outfit hides fully.
3. It binds each garment to its bones, cuts it along its dye pattern and paints it. It gives the garment texture coordinates in meters.
4. It adds each garment as a skinned mesh on the person's skeleton, with its fabric's look and bump map.
5. It hides the scalp's hair under a garment that covers the head. A hat other than a great helm keeps the hair, and lays its strands and cards under its crown. See [Hats and helmets](Garments#hats-and-helmets).

It returns a `Dressed` record: the skinned mesh of each garment, or -1, and each garment's whole shell. `dress` changes the person's skin, so dress a person once.

`outfit_named` gives three outfits.

| Name | Garments |
|---|---|
| `peasant` | shirt, hose, tunic, hood, boots |
| `man-at-arms` | shirt, hose, gambeson, hauberk, coif, boots, gloves |
| `knight` | the man-at-arms's, then cuirass, fauld, pauldrons, vambraces, greaves, surcoat, gorget, gauntlets and sabatons |

## Crowds

A crowd in one outfit looks like a uniform. `extensions/attire/mix.mojo` dresses each person of a crowd by a seed.

```mojo
from extensions.attire.mix import mixed_outfit

var dressed = dress(scene, assets, person, mixed_outfit(person_index))
```

`mixed_calling(seed)` picks a `Calling`. Of each forty seeds, about eight are peasants, six goodwives, six farmers, three archers, three merchants, three men-at-arms, two monks and two rangers. One in forty is each of a noblewoman, a knight, a barbarian, a royal, a wizard, a warlock and a warrior. `mixed_sex(seed)` gives the person's sex.

`calling_outfit(calling, seed)` dresses that calling. `dressed_as(calling, sex, seed)` dresses a person of either sex. The same seed gives the same outfit on every machine.

The first eight callings dress as their own sex: a goodwife and a noblewoman as women, the rest as men. The last seven have clothes for each sex, and about two in five of them are women.

| Calling | Garments |
|---|---|
| `PEASANT` | shirt, breeches over hose, tunic and boots; a hood and a belt by chance |
| `GOODWIFE` | shirt, gown and boots, and a belt; a hood by chance |
| `ARCHER` | shirt, hose, gambeson, jerkin, belt and boots; a hood by chance |
| `MONK` | shirt, robe, hood, belt and boots |
| `MERCHANT` | shirt, hose, tunic, belt and boots; a hood by chance |
| `NOBLEWOMAN` | shirt, gown, belt and boots |
| `MAN_AT_ARMS` | the man-at-arms's outfit and a belt; a surcoat by chance |
| `KNIGHT` | the knight's outfit and a belt |
| `FARMER` | shirt; a smock or a tunic over trousers, or a gown and by chance a bodice; a straw hat and a belt by chance; boots |
| `BARBARIAN` | fur kilt, fur boots, bracers and belt, bare-chested; a woman wears a jerkin; a shirt of iron or bronze scales, more often for women; a fur mantle, and a horned or half helm of iron or bronze, by chance |
| `ROYAL` | a velvet robe or gown in a rich dye, edged in white fur and parti-colored by chance; a royal mantle edged in ermine or gold; a sash; a crown of gold or silver set with a rich stone, or for some queens a circlet; boots |
| `WIZARD` | a wizard's robe in an arcane dye, banded in a second by chance, trimmed in gold or silver; a sash; a hat in the robe's dye or another; some women wear a silver circlet; a gray fur mantle by chance; boots |
| `WARLOCK` | a dark cassock and sash in shadow dyes; a hood, or for some women a blackened circlet; blackened great pauldrons gilt at their edges, or a dark mantle, by chance; tall boots |
| `RANGER` | hose and a tunic in forest greens, bracers and a belt; a jerkin by chance; a feathered cap with a red or white feather, or a hood; a fur mantle by chance; tall boots |
| `WARRIOR` | a gambeson under a platebody or, three times in ten, a shirt of scales, plate legs, arm harness, pauldrons or great pauldrons, a plate skirt or a fauld under a platebody, gauntlets and sabatons, all of one metal; a great helm or a half helm, which some women leave off; a surcoat by chance |

The poor wear the dyes of `plain_dye`: madder, woad, weld, walnut, nettle, gray and cream wool, russet and lichen purple. The rich wear the dyes of `rich_dye`: kermes crimson, deep woad, verdigris, saffron, black and murex violet. A merchant's trim is rich. A knight's surcoat takes two rich dyes per pale. Three plates in ten are blackened against rust.

The new callings take palettes of their own. `fur_dye` gives wolf gray, bear brown, fox red, snow white, black and tawny pelts. `forest_dye` gives the greens and browns of a ranger. `arcane_dye` gives the deep blues, violets and crimsons of a wizard. `shadow_dye` gives the blacks and dark reds of a warlock.

`warrior_metal(seed)` forges a warrior's harness. Of each twenty seeds, about six are steel, three iron and three blackened. Two are blued, two bronze, and one each copper, brass, silver and gold. A quarter of the harnesses are gilt at their edges, and a quarter of the rest brassed.

`calling_hair(calling, sex, seed)` and `calling_beard(calling, sex, seed)` pick a hairstyle and a beard that suit the calling. A woman of a barbarian calling can wear twin braids, and a royal man slicks his hair back. A wizard grows a long beard or a full one, and a barbarian a forked, a full or a long one. A woman is clean-shaven.

`calling_cloak(calling, sex, seed)` picks a cloak, or none. `cloak_of(calling, seed)` gives the cloak of a calling that wears one. Hang it over the outfit as [Cloth and spring bones](Cloth-and-spring-bones#over-garments) shows.

| Calling | Wears one | Cloak | Lining |
|---|---|---|---|
| royal | 3 in 4 | velvet in a rich dye to the ankle, edged in ermine or gold | gold, or a second rich dye |
| warlock | 11 in 20 | wool in a shadow dye to the ankle, edged in red | red |
| ranger | 11 in 20 | wool in a forest dye | a second forest dye |
| knight | 1 in 2 | wool in a rich dye, edged in a second | the second |
| wizard | 9 in 20 | wool in an arcane dye to the ankle, edged in gold or silver | a second arcane dye |
| noblewoman | 2 in 5 | velvet in a rich dye, edged in gold | ermine |
| warrior | 2 in 5 | wool in a rich dye | a second rich dye |
| archer | 7 in 20 | wool in a forest dye | a second forest dye |
| barbarian | 7 in 20 | a short cloak of fur | the hide |
| merchant | 1 in 4 | wool in a rich dye | a second rich dye |
| monk | 1 in 4 | wool in the dye of his robe, to the ankle | the same |
| peasant, goodwife, man-at-arms, farmer | 3 in 20 | plain wool, to the knee | the same |

The seed makes each cloak a little longer or shorter, and fuller or plainer.

Each garment of a calling takes its dye by a pick of its own. So the dyes of a robe, its mantle and its sash vary apart. A test dresses 120 seeds of each of the seven callings as a man and as a woman. Of the 1,680 people, more than 1,500 differ in their garments, dyes, metals, hair or beard. The genome and the stature make each person differ further.

Some garments are parti-colored: four merchants' tunics in ten and three women's gowns in ten take a second dye on the left side. Three men-at-arms' surcoats in ten are quartered, and two in ten bear a cross or a saltire.

A knight's surcoat and a warrior's bear arms that `heraldry(seed, salt)` picks. Of each twenty seeds, about four are plain, three parted per pale, three quartered and three bear a chevron. Two each bear a cross or a saltire, and one each a bend, paly or checky.

`examples/crowd.mojo` draws the eight callings side by side, each with a genome and a stature of their own. Each person's hair and beard suit their calling, and the hair is 400 cards. It writes `out/crowd.png`.

![Eight people of eight callings walk and stand in a studio](out/crowd.png)

### Archetypes

`examples/archetypes.mojo` dresses a farmer, a barbarian, a royal, a wizard, a warlock, a ranger and a warrior, each as a man and a woman. The men stand in front and the women behind. Each person's seed picks a genome, a stature, the dyes, the metals, the headwear and a hairstyle. Each man's calling picks his beard, and each calling a cloak by chance.

The cloaks fall over the outfits' colliders. The hair is 500 cards on each head, moved and shaded by `GameHairMotion`. The camera passes along the front and round to the back. It writes `out/archetypes.png`.

![Fourteen people of seven callings walk and stand while the camera passes round to their cloaks](out/archetypes.png)

## Crowd cost

`bench/crowd_bench.mojo` builds a varied crowd and measures it. A seed gives each person a calling, a sex, a genome, a stature, an outfit, a hairstyle, a beard and, by chance, a cloak. The crowd stands in rows ten wide and four meters apart, and walks in place. The camera looks along the rows from in front.

These are 40 people on four threads, drawn at 1280 by 720 on the CPU:

| Skin budget, cards | Triangles a person | Build | Dress | Hair a frame | Cloaks a frame | Draw a frame |
|---|---|---|---|---|---|---|
| 16,000, 400 | 41,000 | 2.1 s | 0.19 s | 39 ms | 20 ms | 1.8 s |
| 8,000, 200 | 28,000 | 2.0 s | 0.13 s | 20 ms | 15 ms | 1.4 s |
| 4,000, 100 | 21,500 | 1.9 s | 0.08 s | 9 ms | 16 ms | 1.0 s |

Of the 40, 30 stand within 15 m of the camera. Their hair moves, and 11 of the 14 cloaks step. The rest ride their bones. Animating the 40 skeletons takes 3 ms a frame. A person holds about 9 MB after the build at 16,000 triangles.

- The CPU renderer holds about 680 bytes for each triangle it draws. So the 40 people at 16,000 triangles take 1.9 GB to draw.
- The garments, the cloaks and the hats do not scale with the skin's budget. At 4,000 triangles they draw more than half of each person's triangles.
- For thousands of people, build each look once and bake it. A bake loads in 12 ms; see [Game humanoid](Game-humanoid#baking-and-speed). A loaded bake draws its hair and its cloak as they lay when baked.

These changes made a crowd cheaper:

- The hair's shell and the hands are meshed at about ten times their budgets, not finer. The archetypes example built its 14 people in 44.6 s before, and in 32.2 s after.
- `HairCollider` bakes its grid on every thread.
- Hair and cloaks farther than 15 m from the camera ride their bones and are not simulated.
- `move_cloaks` steps the near cloaks at once, and a capsule is tested only near its box. The cloaks fell from 62 ms to 20 ms a frame.
- `move_hair` steps and lights the near grooms at once. The hair fell from 55 ms to 39 ms a frame.

## Plate

A flexible garment keeps the skin's weights and bends as the skin bends. Plate does not bend.

| Articulation | How it rides | Example |
|---|---|---|
| `FLEXIBLE` | the skin's own weights | cloth, leather, mail |
| `RIGID` with an anchor | that one bone | a cuirass on the chest, a bascinet on the head |
| `RIGID` without an anchor | at each vertex, the heaviest bone it covers | greaves on each shin |
| `LAMED` | bands that step from the anchor to the skin's weights | a fauld from the hips, pauldrons from the chest |

A lamed garment is cut into bands along the anchor's own weight on the skin. The top lame rides the anchor wholly. Each lame below it shares more of its weight with the bones under it, in equal steps. Each lame reaches 0.3 of a band past its lower bound and stands 2.5 mm out over the lame below. So each lame shows its lower edge as a lip, and the fauld opens as the thigh lifts.

## Sockets and props

A socket is a named place on the body that rides one bone. Each socket is placed from the rig's landmarks and scaled with its stature.

| Socket | Rides |
|---|---|
| `CROWN` | head |
| `BACK` | chest |
| `RIGHT_HIP`, `LEFT_HIP`, `BELT_FRONT` | hips |
| `RIGHT_SHOULDER`, `LEFT_SHOULDER` | chest |
| `RIGHT_GRIP`, `LEFT_GRIP` | each hand |

`attach(scene, person, socket, node)` hangs a node from the socket's bone, at the socket. The node keeps its rotation, so turn a shield or a scabbard before you attach it.

`heater_shield(height, dexter, sinister)` gives a flat-topped shield, curved across and painted per pale. `sword_in_scabbard(length)` gives the leather and the steel of a sword in its scabbard, as two meshes.

`heraldic_shield(height, pattern, field, charge, rim)` gives the same shield bearing arms. It lays any dye pattern on its face, in the shield's own lengths:

- The charges cross at the fess point, 40 % of the height down from the top.
- A band of a cross, a saltire, a chevron or a bend is a fifth of the width wide. Six pales, stripes or checks run across the width.
- The face is cut along each boundary, so each edge is crisp. A rim of metal runs round the edge.

`calling_arms(calling, seed)` gives the arms of a soldier of a calling, or none. A knight and a warrior bear the arms of their surcoat, by the same seed. A man-at-arms bears his company's plain dyes. In `examples/archetypes.mojo`, a warrior with no cloak carries a shield of arms on the back.

```mojo
var slung = Object3D()
slung.rotate_y(Angle(180.0, DEGREE))
var back = attach(scene, person, BACK, slung^)
scene.add_mesh(Mesh(assets.geometries.add(heater_shield(height, blue, white)), paint, back))
```

## Saved outfits and dressed bakes

A player saves a look and puts it on again, on the same body or another. `outfit_json` writes an outfit as one JSON object. `outfit_from_json` reads it back. Slots, layers, fabrics, articulations, patterns and forms are written by name, anchors by joint name, dyes as sRGB bytes, and the flare as a number. A garment saved without a form reads as fitted, with no flare.

`write_dressed_bake` writes a sealed bake of a dressed humanoid. The geometry digest covers every garment, so dress before you bake. The scene extras keep the outfit under `OUTFIT_KEY`, with the fingerprint of the spec it was fitted to. `stored_outfit(extras, spec)` gives the outfit back and refuses it for another body.

## Example

`examples/armory.mojo` dresses a peasant woman, a man-at-arms and a knight, each of their own build. It hangs a cloak on the peasant, a shield and a sword on the man-at-arms, and a sword on the knight. The three walk while the camera turns round them. It writes `out/armory.png`.

```bash
.venv/bin/mojo run -I . examples/armory.mojo out/armory.png
```

## Tests

`tests/test_attire_outfit.mojo`, `test_attire_preset.mojo`, `test_attire_mix.mojo`, `test_attire_armory.mojo`, `test_attire_headwear.mojo` and `test_attire_sockets.mojo` cover this page.
