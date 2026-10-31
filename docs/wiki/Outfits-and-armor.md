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
| `BARBARIAN` | fur kilt, fur boots, bracers and belt, bare-chested; a woman wears a jerkin; a fur mantle, and a horned or half helm of iron or bronze, by chance |
| `ROYAL` | a velvet robe or gown in a rich dye, edged in white fur, a royal mantle and a sash; a crown of gold or silver, or for some queens a circlet; boots |
| `WIZARD` | a wizard's robe, sash and hat in an arcane dye, trimmed in gold or silver; some women wear a silver circlet; boots |
| `WARLOCK` | a black cassock trimmed in red and a sash; a hood, or for some women a blackened circlet; a dark mantle by chance; tall boots |
| `RANGER` | hose, a tunic in forest green, bracers and a belt; a jerkin by chance; a feathered cap with a red or white feather, or a hood; tall boots |
| `WARRIOR` | a gambeson under a platebody, plate legs, arm harness, pauldrons or great pauldrons, a plate skirt or a fauld, gauntlets and sabatons, all of one metal; a great helm or a half helm, which some women leave off; a surcoat by chance |

The poor wear the dyes of `plain_dye`: madder, woad, weld, walnut, nettle, gray and cream wool, russet and lichen purple. The rich wear the dyes of `rich_dye`: kermes crimson, deep woad, verdigris, saffron, black and murex violet. A merchant's trim is rich. A knight's surcoat takes two rich dyes per pale. Three plates in ten are blackened against rust.

The new callings take palettes of their own. `fur_dye` gives wolf gray, bear brown, fox red, snow white, black and tawny pelts. `forest_dye` gives the greens and browns of a ranger. `arcane_dye` gives the deep blues, violets and crimsons of a wizard. `shadow_dye` gives the blacks and dark reds of a warlock.

`warrior_metal(seed)` forges a warrior's harness. Of each twenty seeds, about six are steel, three iron and three blackened. Two are blued, two bronze, and one each copper, brass, silver and gold. A quarter of the harnesses are gilt at their edges, and a quarter of the rest brassed.

Each calling of the seven has about a dozen choices of cut, dye, metal and headwear for each sex. With the genome, the stature, the hair and the beard of each person, a crowd of thousands has few twins.

Some garments are parti-colored: four merchants' tunics in ten and three women's gowns in ten take a second dye on the left side. Three men-at-arms' surcoats in ten are quartered.

`examples/crowd.mojo` draws the eight callings side by side, each with a genome and a stature of their own. It writes `out/crowd.png`.

![Eight people of eight callings walk and stand in a studio](out/crowd.png)

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
