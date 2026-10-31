# Village combos

A combo is a string of presses that ends in a strong finisher. A style's skill level teaches its combos, and each combo ranks up as the player makes it. Anyone can make the basic combos. The hardest combos need each press on the beat.

The module is `extensions/village/combos.mojo`. See [Village fighting styles](Village-styles) for the styles, and [Village skills](Village-skills) for the levels.

## The keys

Each press of the fight is a `ComboKey`:

| Key | Letter | Press |
|---|---|---|
| `LIGHT_KEY` | `L` | The light attack |
| `HEAVY_KEY` | `H` | The heavy attack |
| `DODGE_KEY` | `D` | The dodge |
| `JUMP_KEY` | `J` | The jump |
| `GUARD_KEY` | `G` | A tap of the guard |

A `ComboTracker` keeps the last 8 keys of the string. A key more than a second after the key before it starts a new string. A special breaks the string.

## The beat

A key pressed as the move before it lands is on the beat. For an attack, the beat is from 0.06 seconds before the end of its active part to 0.16 seconds after it. For a dodge, the beat is its last 0.22 seconds. See `on_beat`.

An attack pressed on the beat does 10 percent more damage, in a combo or out of one. `ON BEAT` flashes over the combo counter. A jump that cuts an attack's recovery short is on the beat.

## The finisher

When the string ends in a combo that the player knows, its finisher starts in place of the key's own move. The finisher does the combo's power times its damage, and spends no special points. The note names the combo. The longest combo that the string ends in wins, so a short combo can end a long string.

A heavy finisher in the air is a plunge. A finisher that cannot start, as in a stagger, leaves the string as it is.

## The tiers

`ComboTier` says how hard a combo is:

| Tier | What it asks | Levels |
|---|---|---|
| `BASIC` | Two or three keys, none on the beat | 1 and 2 |
| `ADVANCED` | A dodge, a jump or a guard among its keys | 3 to 5 |
| `EXPERT` | Keys on the beat | 6 and 7 |
| `MASTER` | A long string, nearly every key on the beat | 9, in the specialty only |

## The catalog

In a pattern, a key that ends in `*` must be on the beat. The power is the finisher's times its damage at rank 1.

| Style | Combo | Tier | Level | Keys | Finisher | Power |
|---|---|---|---|---|---|---|
| Sword | RISING STRIKE | Basic | 1 | `L L H` | `RISING_EDGE` | 1 |
| Sword | CROSS CUT | Basic | 2 | `L H` | `HEAVY` | 1.25 |
| Sword | TEMPEST | Advanced | 3 | `L L L H` | `WHIRLWIND` | 1.2 |
| Sword | DASH CUT | Advanced | 4 | `D L` | `LIGHT_THREE` | 1.5 |
| Sword | RIPOSTE | Advanced | 5 | `G L` | `LIGHT_THREE` | 1.8 |
| Sword | RIVER OF STEEL | Expert | 6 | `L L* H*` | `GROUND_WAVE` | 1.6 |
| Sword | SKY BREAKER | Expert | 7 | `L L* J L H` | `PLUNGE` | 1.8 |
| Sword | THOUSAND CUTS | Master | 9 | `L L* L* D L* L* H*` | `WHIRLWIND` | 2.6 |
| Hand to hand | UPPERCUT | Basic | 1 | `L L H` | `RISING_EDGE` | 1 |
| Hand to hand | BODY BLOW | Basic | 2 | `L H` | `HEAVY` | 1.3 |
| Hand to hand | FLURRY | Advanced | 3 | `L L L L` | `LIGHT_THREE` | 1.5 |
| Hand to hand | SPINNING HEEL | Advanced | 4 | `D H` | `WHIRLWIND` | 1.3 |
| Hand to hand | RISING DRAGON | Expert | 6 | `L L* L* H*` | `RISING_EDGE` | 1.9 |
| Hand to hand | EARTHSHAKER | Expert | 7 | `J L H*` | `PLUNGE` | 1.7 |
| Hand to hand | STORM OF FISTS | Master | 9 | `L L* L* L* L* L* H*` | `WHIRLWIND` | 2.8 |
| Axe | CLEAVER | Basic | 1 | `L L H` | `HEAVY` | 1.2 |
| Axe | HEWING ARC | Basic | 2 | `L H` | `WHIRLWIND` | 1 |
| Axe | TIMBER | Advanced | 3 | `H H` | `HEAVY` | 1.5 |
| Axe | REAVER SPIN | Advanced | 5 | `L L L H` | `WHIRLWIND` | 1.4 |
| Axe | SPLITTER | Expert | 7 | `D H*` | `RISING_EDGE` | 1.8 |
| Axe | WORLD SPLITTER | Master | 9 | `L L* H* H*` | `GROUND_WAVE` | 2.6 |
| Mace | BONEBREAKER | Basic | 1 | `L H` | `HEAVY` | 1.25 |
| Mace | BELL RINGER | Basic | 2 | `L L H` | `RISING_EDGE` | 1 |
| Mace | QUAKE | Advanced | 4 | `H H` | `GROUND_WAVE` | 1.4 |
| Mace | IRON TIDE | Advanced | 5 | `L L L H` | `WHIRLWIND` | 1.3 |
| Mace | PILEDRIVER | Expert | 7 | `J H*` | `PLUNGE` | 2 |
| Mace | JUDGMENT | Master | 9 | `L L* H* G H*` | `GROUND_WAVE` | 2.8 |
| Magic | SPARK CHAIN | Basic | 1 | `L L L` | `SPELL_BLAST` | 1.2 |
| Magic | ARCANE RING | Basic | 2 | `L H` | `NOVA` | 1 |
| Magic | BLINK BLAST | Advanced | 3 | `D L` | `SPELL_BLAST` | 1.3 |
| Magic | SANCTUARY | Advanced | 5 | `G H` | `MEND` | 1.4 |
| Magic | STARBURST | Expert | 7 | `L L* L* H*` | `NOVA` | 1.9 |
| Magic | COMET | Master | 9 | `L L* D L* H* H*` | `SPELL_BLAST` | 3 |
| Archery | PINNING SHOT | Basic | 1 | `L L H` | `AIMED_SHOT` | 1.2 |
| Archery | SCATTER | Basic | 2 | `L H` | `VOLLEY` | 1 |
| Archery | EVASIVE SHOT | Advanced | 3 | `D L` | `LEAP_SHOT` | 1.3 |
| Archery | PIERCING GALE | Advanced | 5 | `H H` | `AIMED_SHOT` | 1.5 |
| Archery | HAILSTORM | Expert | 7 | `L L* L* H*` | `ARROW_RAIN` | 1.6 |
| Archery | HUNTER'S MOON | Master | 9 | `L L* D L* H*` | `AIMED_SHOT` | 3 |

A mend's power heals more. SANCTUARY heals 1.4 times as much as a plain mend.

## Mastery

`ComboBook` holds every combo, which ones the player knows, and each one's mastery. Each finisher made gives 2 mastery, and each that lands gives 3 more. A combo's rank rises from 1 to 5. Rank `r` needs `rank_mastery(r)`: 20 times `r - 1` times `r`.

| Rank | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| Mastery | 0 | 40 | 120 | 240 | 400 |
| Power | 1 times | 1.1 times | 1.2 times | 1.3 times | 1.4 times |

The note says when a combo ranks up, such as `RISING STRIKE RANK 2!`, and `RISING STRIKE MASTERED!` at rank 5. It says `NEW COMBO:` and the name when a level teaches one.

## Perks

A combo's rank also upgrades its finisher. A perk acts when the finisher lands.

| Rank | Perk |
|---|---|
| 3 and 4 | The finisher gives back the stamina it spent. |
| 5, mastered | The finisher gives back its stamina, and gives one special point. |

So a player who masters a combo can chain finishers and specials for longer. The book shows `MASTERED` for a combo at rank 5.

## What shows

Over the combo counter, the display lists up to three combos that the string is on the way to. A combo's keys done are gold, the next is white, and the rest are gray. A key that must be on the beat has an orange dot under it.

The book button shows the combo book: each combo of the player's style, its tier, its keys and its rank, or `MASTERED`. A combo not yet learned shows the level that teaches it, or `SPECIALTY` for a master combo of another style.

| Control | Gamepad | Keyboard |
|---|---|---|
| Show the combo book | Hold the left trigger, and press the back button | `K` |

## Limits

- The game keeps each combo's mastery from one game to the next: see [Village walk](Village-walk#saved-progress). The combos learned are not kept, because the levels teach them again.
- A finisher is one of the existing moves. A combo has no clip of its own.
