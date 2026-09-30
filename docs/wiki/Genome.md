# Genome

A `Genome` sets the heritable traits of a humanoid. It sets the skin's tone, the hair's and the eyes' color, the frame's proportions, and the shape of the head and the face. Give a genome to `HumanoidSpec`, and every layer of the body reads it.

![Six heads from six genomes turn a little to each side](out/genomes.png)

The module is `extensions/humanoid/genome.mojo`. This is not a three.js port. See [Extensions](Extensions).

## Call it

```mojo
from extensions.humanoid.athleticism import TONED
from extensions.humanoid.genome import (
    MELANIN,
    NOSE_LENGTH,
    Expression,
    Genome,
    offspring,
    random_genome,
)
from extensions.humanoid.sex import FEMALE, MALE
from extensions.humanoid.spec import HumanoidSpec
from units.si import FOOT, Length

var genome = Genome().with_gene(MELANIN, Expression(0.6)).with_gene(
    NOSE_LENGTH, Expression(-0.3)
)
var person = HumanoidSpec(Length(6.0, FOOT), MALE, TONED, genome)
var cousin = HumanoidSpec(Length(5.5, FOOT), FEMALE, TONED, random_genome(7))
var child = offspring(genome, random_genome(7), 3)
```

`Genome()` is the template: every gene at zero. A spec without a genome holds the template, so a body made before genomes existed does not change shape.

Each gene takes an `Expression` from -1 through 1. Zero is the template. The sign says which way the trait moves. At 1 or -1 a trait is near the edge of the adult range. It is not past it.

A bare integer for a gene is a compile error, and so is a bare float for an expression. `with_gene` raises for a gene that is not named or an expression outside -1 through 1. Every boundary that reads a genome calls `check_genome`, which refuses one that is not valid.

## Genes

| Gene | At -1 | At 1 | What it moves |
|---|---|---|---|
| `MELANIN` | Very fair skin | Very dark skin | The skin's tone, from Fitzpatrick type I to type VI |
| `UNDERTONE` | Cool, pink | Warm, olive | The skin's hue |
| `FRECKLES` | None | Many | Freckles in the skin's map, fewer on dark skin |
| `HAIR_MELANIN` | Platinum blond | Black | The hair's and the brows' color |
| `HAIR_REDNESS` | No red | Auburn, copper | The hair's red |
| `IRIS_MELANIN` | Blue | Dark brown | The iris's color |
| `EYE_SIZE` | Small | Large | The eyeball and the opening of the lids |
| `EYE_SPACING` | Close-set | Wide-set | The orbits, the eyes and the lids |
| `EYE_TILT` | Outer corners down | Outer corners up | The canthal tilt |
| `EYE_DEPTH` | Prominent | Deep-set | The eyes in their orbits |
| `BROW_HEIGHT` | Low | High | The brows over the eyes |
| `BROW_THICKNESS` | Fine | Full | The eyebrows' hair |
| `BROW_ARCH` | Flat | Arched | The middle of each brow |
| `NOSE_LENGTH` | Short | Long | The nose from its root to its tip |
| `NOSE_WIDTH` | Narrow | Broad | The wings of the nose |
| `NOSE_PROJECTION` | Flat | Projecting | The tip, forward from the face |
| `NOSE_BRIDGE` | Low | High | The bridge between the eyes |
| `MOUTH_WIDTH` | Narrow | Wide | The mouth from corner to corner |
| `LIP_FULLNESS` | Thin | Full | Both lips |
| `EAR_SIZE` | Small | Large | The auricle |
| `EAR_PROTRUSION` | Close to the head | Standing out | The flare of each ear's back edge |
| `EAR_LOBE` | Attached | Large and free | The lobe |
| `HEAD_WIDTH` | Narrow | Broad | The cranium's breadth |
| `HEAD_LENGTH` | Short | Long | The cranium from front to back |
| `HEAD_HEIGHT` | Low | Tall | The vault above the ears |
| `JAW_WIDTH` | Narrow | Broad | The mandible at its angles |
| `CHIN` | Receding | Strong | The chin forward and down |
| `CHEEKBONES` | Flat | High, prominent | The cheekbones out and forward |
| `BROW_RIDGE` | Smooth | Heavy | The brow ridge over the eyes |
| `NECK_LENGTH` | Short | Long | The neck between its base and the skull |
| `SHOULDER_BREADTH` | Narrow | Broad | The rib cage and the shoulders |
| `CHEST_DEPTH` | Shallow | Deep | The rib cage from front to back |
| `ARM_LENGTH` | Short | Long | The upper arm and the forearm |
| `HAIR_LENGTH` | Cropped close | A bob to the jaw | The scalp's hair |

`named_genes()` returns every gene in this order. Hair is cut as well as grown, so `HAIR_LENGTH` is a look more than a trait. `gene_label(gene)` returns its lowercase name.

The genes are authored controls. They are not a model of the loci that set these traits in people. Many small genes set each trait, and growth and the environment change them too.

## How a body reads its genome

The skin's genes set its looks. `skin_tone(genome)` walks a ramp of six swatches for `MELANIN`, then moves the result toward pink or olive for `UNDERTONE`. `skin_albedo(size, genome)` adds broad blotches of redness and pigment, pores, freckles and a rare mole. `hair_tone` and `iris_tone` do the same for the hair and the iris. See [Head](Head#skin-and-hair).

The head's and the face's genes move the head's landmarks. Each landmark is authored in centimeters on the six-foot template, and `HeadMorph` moves it before the frame places it. Each gene is a smooth displacement in its own region. The nose's genes move the points near the nose, and the eyes' genes the points round each orbit. The skull, the muscles, the vessels, the skin and the hair all move together, so the anatomy stays inside the skin. Below the base of the neck the morph does nothing, so the neck still meets the torso.

The ears are skin alone, so the skin shapes them itself: `ear_frame(size, protrusion)` sets the plane each ear is authored in.

The frame's genes change the torso's frame. `SHOULDER_BREADTH` widens the rib cage and the shoulder girdle, most at the shoulders and not at all at the waist. The arms hang from the wider girdle. `CHEST_DEPTH` deepens the rib cage in front of and behind the spine. `ARM_LENGTH` stretches the upper arm and the forearm. The hand keeps its size.

The female template's face differs from the male one's as the averages of the two differ. It has a smaller brow ridge and nose, a narrower jaw and a smaller chin. It has slightly larger eyes, fuller lips and a longer neck. `HeadMorph` adds those offsets to the genes.

## Inheritance

`random_genome(seed)` draws a plausible genome. The same seed always gives the same genome. Most traits land near the template. The pigment genes are linked as they are in people: dark skin rarely comes with blond hair, freckles or blue eyes.

`offspring(mother, father, seed)` returns a child. Each gene lands between the two parents' expressions, with a small mutation of at most 0.1. It raises if a parent's genome is not valid.

## Looks

`add_complexion(assets, genome, whole_body)` stores the looks one genome asks for and returns their ids in a `Complexion`:

| Field | Look |
|---|---|
| `skin` | `skin_physical` with the tone, a tiled color map and pore relief, tinted by the face's zones, with light through thin skin |
| `hair` | `hair_physical` with a map of strands |
| `eyes` | `eye_physical` with the iris's map |

Pass `whole_body=True` for the skin of `add_body`, which is taller than the head's and tiles more times up it.

The skin is tinted: every mesh it paints must carry a `color` attribute. The head's skin and the body's skin carry one. `untinted(geometry)` gives another mesh a white one. See [Head](Head#skin-and-hair).

## Examples

`examples/genomes.mojo` draws six heads from six genomes and turns each a little to each side. It writes `out/genomes.png`.

`examples/family.mojo` draws two parents and their two grown children, whole, and turns them. Each child is the `offspring` of the parents. It writes `out/family.png`.

![Two parents and their two grown children turn in a row](out/family.png)

```bash
.venv/bin/mojo run -I . examples/genomes.mojo out/genomes.png high 24
.venv/bin/mojo run -I . examples/family.mojo out/family.png high 36
```
