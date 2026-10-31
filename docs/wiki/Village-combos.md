# Village combos

A combo is a string of presses that ends in a strong finisher. A style's skill level teaches its combos, and each combo ranks up as the player makes it. Anyone can make the basic combos. The hardest combos need each press on the beat.

Each style has ten combos: two basic, three advanced, three expert and two master. Most finishers also have an effect, such as a wound that bleeds or sparks that leap to other foes: see [Effects](#effects).

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

When the string ends in a combo that the player knows, its finisher starts in place of the key's own move. The finisher does the combo's power times its damage, and spends no special points. The note names the combo.

`ComboBook.match` chooses the combo by these rules:

1. Of the combos that the string ends in, the longest wins. So a short combo can end a long string.
2. Of two combos as long, the one with more keys on the beat wins. So `L L* H*` on the beat makes RIVER OF STEEL, not RISING STRIKE.
3. A longer combo that the string is on its way to holds a shorter one back. Its first keys, beats and all, must be at least as many of the string's last keys as the shorter combo has. So `D L*` inside THOUSAND CUTS does not make DASH CUT. Off the beat, `D L` still makes DASH CUT.

Each combo can be made from its own keys: a test makes all 60 of them.

A heavy finisher in the air is a plunge. A finisher that cannot start, as in a stagger, leaves the string as it is.

## The tiers

`ComboTier` says how hard a combo is:

| Tier | What it asks | Levels | A style has |
|---|---|---|---|
| `BASIC` | Two or three keys, none on the beat | 1 and 2 | 2 |
| `ADVANCED` | A dodge, a jump or a guard among its keys | 3 to 5 | 3 |
| `EXPERT` | Keys on the beat | 6 to 8 | 3 |
| `MASTER` | A long string, nearly every key on the beat | 9, in the specialty only | 2 |

## The catalog

In a pattern, a key that ends in `*` must be on the beat. The power is the finisher's times its damage at rank 1.

| Style | Combo | Tier | Level | Keys | Finisher | Power | Effect |
|---|---|---|---|---|---|---|---|
| Sword | RISING STRIKE | Basic | 1 | `L L H` | `RISING_EDGE` | 1 | `LAUNCH` |
| Sword | CROSS CUT | Basic | 2 | `L H` | `HEAVY` | 1.25 | `BLEED` |
| Sword | TEMPEST | Advanced | 3 | `L L L H` | `WHIRLWIND` | 1.2 | `SHOCKWAVE` |
| Sword | DASH CUT | Advanced | 4 | `D L` | `LIGHT_THREE` | 1.5 | `MARK` |
| Sword | RIPOSTE | Advanced | 5 | `G L` | `LIGHT_THREE` | 1.8 | `SUNDER` |
| Sword | RIVER OF STEEL | Expert | 6 | `L L* H*` | `GROUND_WAVE` | 1.6 | `BLEED` |
| Sword | SKY BREAKER | Expert | 7 | `L L* J L H` | `PLUNGE` | 1.8 | `SHOCKWAVE` |
| Sword | CRESCENT | Expert | 8 | `D L* H*` | `WHIRLWIND` | 1.9 | `LAUNCH` |
| Sword | HEAVEN'S EDGE | Master | 9 | `G L* L* J H*` | `PLUNGE` | 2.8 | `SUNDER` |
| Sword | THOUSAND CUTS | Master | 9 | `L L* L* D L* L* H*` | `WHIRLWIND` | 2.6 | `BLEED` |
| Hand to hand | UPPERCUT | Basic | 1 | `L L H` | `RISING_EDGE` | 1 | `LAUNCH` |
| Hand to hand | BODY BLOW | Basic | 2 | `L H` | `HEAVY` | 1.3 | `DRAIN` |
| Hand to hand | FLURRY | Advanced | 3 | `L L L L` | `LIGHT_THREE` | 1.5 | `MARK` |
| Hand to hand | SPINNING HEEL | Advanced | 4 | `D H` | `WHIRLWIND` | 1.3 | `SHOCKWAVE` |
| Hand to hand | PALM STRIKE | Advanced | 5 | `G H` | `HEAVY` | 1.5 | `SUNDER` |
| Hand to hand | RISING DRAGON | Expert | 6 | `L L* L* H*` | `RISING_EDGE` | 1.9 | `LAUNCH` |
| Hand to hand | EARTHSHAKER | Expert | 7 | `J L H*` | `PLUNGE` | 1.7 | `SHOCKWAVE` |
| Hand to hand | TIGER CLAW | Expert | 8 | `D L* H*` | `GROUND_WAVE` | 1.8 | `BLEED` |
| Hand to hand | STORM OF FISTS | Master | 9 | `L L* L* L* L* L* H*` | `WHIRLWIND` | 2.8 | `DRAIN` |
| Hand to hand | THUNDER PALMS | Master | 9 | `G L* L* L* H*` | `WHIRLWIND` | 2.8 | `CHAIN` |
| Axe | CLEAVER | Basic | 1 | `L L H` | `HEAVY` | 1.2 | `BLEED` |
| Axe | HEWING ARC | Basic | 2 | `L H` | `WHIRLWIND` | 1 |  |
| Axe | TIMBER | Advanced | 3 | `H H` | `HEAVY` | 1.5 | `SUNDER` |
| Axe | HEADSMAN | Advanced | 4 | `G H` | `HEAVY` | 1.6 | `MARK` |
| Axe | REAVER SPIN | Advanced | 5 | `L L L H` | `WHIRLWIND` | 1.4 | `BLEED` |
| Axe | BLOOD ARC | Expert | 6 | `L H* L*` | `RISING_EDGE` | 1.7 | `BLEED` |
| Axe | SPLITTER | Expert | 7 | `D H*` | `RISING_EDGE` | 1.8 | `LAUNCH` |
| Axe | TIMBERFALL | Expert | 8 | `J H*` | `PLUNGE` | 1.9 | `SHOCKWAVE` |
| Axe | BUTCHER'S WALTZ | Master | 9 | `D L* L* H* H*` | `WHIRLWIND` | 2.8 | `BLEED` |
| Axe | WORLD SPLITTER | Master | 9 | `L L* H* H*` | `GROUND_WAVE` | 2.6 | `SHOCKWAVE` |
| Mace | BONEBREAKER | Basic | 1 | `L H` | `HEAVY` | 1.25 | `SUNDER` |
| Mace | BELL RINGER | Basic | 2 | `L L H` | `RISING_EDGE` | 1 | `MARK` |
| Mace | CRUSHING BLOW | Advanced | 3 | `G H` | `HEAVY` | 1.6 | `SUNDER` |
| Mace | QUAKE | Advanced | 4 | `H H` | `GROUND_WAVE` | 1.4 | `SHOCKWAVE` |
| Mace | IRON TIDE | Advanced | 5 | `L L L H` | `WHIRLWIND` | 1.3 | `LAUNCH` |
| Mace | THUNDERCLAP | Expert | 6 | `D H*` | `GROUND_WAVE` | 1.8 | `SHOCKWAVE` |
| Mace | PILEDRIVER | Expert | 7 | `J H*` | `PLUNGE` | 2 | `SHOCKWAVE` |
| Mace | SKULLCRACKER | Expert | 8 | `L H* H*` | `HEAVY` | 1.9 | `MARK` |
| Mace | JUDGMENT | Master | 9 | `L L* H* G H*` | `GROUND_WAVE` | 2.8 | `SUNDER` |
| Mace | MOUNTAIN FALL | Master | 9 | `G H* J H*` | `PLUNGE` | 2.8 | `SHOCKWAVE` |
| Magic | SPARK CHAIN | Basic | 1 | `L L L` | `SPELL_BLAST` | 1.2 | `CHAIN` |
| Magic | ARCANE RING | Basic | 2 | `L H` | `NOVA` | 1 |  |
| Magic | BLINK BLAST | Advanced | 3 | `D L` | `SPELL_BLAST` | 1.3 | `SHOCKWAVE` |
| Magic | WITHERING HEX | Advanced | 4 | `H L` | `SPELL_BLAST` | 1.3 | `MARK` |
| Magic | SANCTUARY | Advanced | 5 | `G H` | `MEND` | 1.4 |  |
| Magic | CHAIN LIGHTNING | Expert | 6 | `L L* H*` | `SPELL_BOLT` | 1.7 | `CHAIN` |
| Magic | STARBURST | Expert | 7 | `L L* L* H*` | `NOVA` | 1.9 | `SHOCKWAVE` |
| Magic | SOUL SIPHON | Expert | 8 | `G L* H*` | `SPELL_BLAST` | 1.8 | `DRAIN` |
| Magic | COMET | Master | 9 | `L L* D L* H* H*` | `SPELL_BLAST` | 3 | `SHOCKWAVE` |
| Magic | STORM CALLER | Master | 9 | `D L* L* H* H*` | `NOVA` | 3 | `CHAIN` |
| Archery | PINNING SHOT | Basic | 1 | `L L H` | `AIMED_SHOT` | 1.2 | `MARK` |
| Archery | SCATTER | Basic | 2 | `L H` | `VOLLEY` | 1 |  |
| Archery | EVASIVE SHOT | Advanced | 3 | `D L` | `LEAP_SHOT` | 1.3 |  |
| Archery | HUNTER'S MARK | Advanced | 4 | `G L` | `QUICK_SHOT` | 1.4 | `MARK` |
| Archery | PIERCING GALE | Advanced | 5 | `H H` | `AIMED_SHOT` | 1.5 | `BLEED` |
| Archery | SERPENT ARROW | Expert | 6 | `L H* L*` | `AIMED_SHOT` | 1.7 | `BLEED` |
| Archery | HAILSTORM | Expert | 7 | `L L* L* H*` | `ARROW_RAIN` | 1.6 | `SHOCKWAVE` |
| Archery | BURSTING VOLLEY | Expert | 8 | `D H*` | `VOLLEY` | 1.8 | `SHOCKWAVE` |
| Archery | HUNTER'S MOON | Master | 9 | `L L* D L* H*` | `AIMED_SHOT` | 3 | `MARK` |
| Archery | RAIN OF RUIN | Master | 9 | `G L* L* H* H*` | `ARROW_RAIN` | 3 | `SHOCKWAVE` |

A mend's power heals more. SANCTUARY heals 1.4 times as much as a plain mend.

The combos added after the first 39 come last in `default_combos`. A saved progress keeps each combo's mastery in that order, so an earlier save still reads.

## Effects

`ComboEffect` is a type with `is_valid`. A combo's effect acts once, on the first target that its finisher lands on. Its word shows over the target in violet, and a flash of light shows how it acts.

| Effect | What it does | Its light |
|---|---|---|
| `LAUNCH` | Throws a bandit or a wolf up at 7 meters a second, to juggle it | A white streak that rises |
| `SUNDER` | Breaks a foe's guard, and empties its stamina. A boss loses 300 poise | Blue shards that burst out |
| `BLEED` | A wound bleeds 60 percent of the blow's damage over 4 seconds. A number shows each half second. A wound does not fell a target | Red drops that fall, and a drop that pulses on the target |
| `DRAIN` | Heals the player by 35 percent of the blow's damage | Green motes that run to the player |
| `SHOCKWAVE` | Strikes each other target within 3.5 meters with half the blow | A gold ring that spreads over the ground |
| `CHAIN` | Sparks leap to up to 3 other targets within 8 meters, each with 60 percent of the blow | A crooked violet arc to each target |
| `MARK` | For 6 seconds, each blow on the target does 1.25 times its damage, from any member | A gold ring that closes, and a gold reticle that turns over the target |

The effects are in `extensions/village/battle.mojo`, and their light in `extensions/village/effects_hud.mojo`.

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

The book button shows the combo book: each combo of the player's style, its tier, its effect, its keys and its rank, or `MASTERED`. A combo not yet learned shows the level that teaches it, or `SPECIALTY` for a master combo of another style.

| Control | Gamepad | Keyboard |
|---|---|---|
| Show the combo book | Hold the left trigger, and press the back button | `K` |

## Limits

- The game keeps each combo's mastery from one game to the next: see [Village walk](Village-walk#saved-progress). The combos learned are not kept, because the levels teach them again.
- A finisher is one of the existing moves. A combo has no clip of its own.
