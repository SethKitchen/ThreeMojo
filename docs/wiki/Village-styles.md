# Village fighting styles

A player of the [Village walk](Village-walk) fights in one of six styles: hand to hand, the sword, the axe, the mace, magic or archery. Each style has its own weapon, its own clips, its own skill and its own combos. The swap button takes up the next style the player carries.

![Six fighters in a row, one for each style, punch, cut, chop, smash, cast and shoot](out/fighting_styles.png)

`examples/fighting_styles.mojo` draws this picture. From the left, each fighter presses its style's buttons in turn: three light attacks, the heavy attack and the three specials. The fists are quickest, and the mace is slowest.

## The styles

The module is `extensions/village/styles.mojo`. `FightingStyle` is a type with `is_valid`. A bare integer does not compile.

| Style | Its weapon | What it is good at |
|---|---|---|
| `HAND_TO_HAND` | Fists and feet | Quick, cheap blows. Its combos grow twice as fast, and its chain point comes at once. |
| `SWORD` | A one-handed sword | Even in every way. |
| `AXE` | A bearded axe | Hard, wide cuts that tear through guards. |
| `MACE` | A flanged mace | Slow blows that break stamina, and hurt through a guard. |
| `MAGIC` | A staff with a crystal | Bolts, blasts, a nova and a mend, paid for with mana. Its guard is a ward all around. |
| `ARCHERY` | A recurve bow | Quick shots, aimed shots, a volley, a leap back and a rain of arrows. |

## The traits

`StyleTraits` change each weapon move, from `LIGHT_ONE` to `PLUNGE`. `style_traits` gives each style's:

| Style | Pace | Power | Reach | Arc | Stamina damage | Stamina | Guard damage | Through a guard | Combo step | Dodge | Parry | Chain point |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Hand to hand | 0.72 | 0.6 | 0.75 | 1 | 0.9 | 0.55 | 1 | 0 | 2 | 1.2 | 1.3 | 0 |
| Sword | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 0 | 1 | 1 | 1 | 0.3 |
| Axe | 1.12 | 1.3 | 1.05 | 1.3 | 1.1 | 1.15 | 1.7 | 0.1 | 1 | 0.95 | 0.8 | 0.4 |
| Mace | 1.28 | 1.15 | 0.95 | 1 | 1.9 | 1.25 | 1.4 | 0.35 | 1 | 0.9 | 0.8 | 0.5 |
| Magic | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 0 | 1 | 1 | 0.6 | 0.3 |
| Archery | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 0 | 1 | 1.25 | 0.7 | 0.2 |

Pace, power, reach, arc, stamina damage and stamina are times the move's own. Guard damage is times the stamina that a guard loses to the style's blows. "Through a guard" is the share of a blow's damage that a guard does not stop. The combo step is times the step of a combo's damage. The dodge is times the dodge's length, and the parry is times the fighter's parry window. The chain point is the share of the recovery after which a waiting move starts.

A mace's blow on a guard takes stamina and some health. A mace blow of 100 damage takes 35 health through the guard. A guard that runs out of stamina breaks, and a guard with no health left falls.

## The buttons and the moves

`FightButton` names what the player presses. `style_move` gives the move that a button makes in a style:

| Button | Melee | Magic | Archery |
|---|---|---|---|
| Light | The next light attack of the chain | `SPELL_BOLT` | `QUICK_SHOT` |
| Heavy | `HEAVY`, or `PLUNGE` in the air | `SPELL_BLAST` | `AIMED_SHOT` |
| Rising | `RISING_EDGE` | `MEND` | `LEAP_SHOT` |
| Whirlwind | `WHIRLWIND` | `NOVA` | `VOLLEY` |
| Wave | `GROUND_WAVE` | `GROUND_WAVE` | `ARROW_RAIN` |
| Ultimate | `ULTIMATE` | `ULTIMATE` | `ULTIMATE` |

The new moves, in the middle stance:

| Move | Start-up | Active | Recovery | What it sends | Damage | Stamina damage | Cost |
|---|---|---|---|---|---|---|---|
| `SPELL_BOLT` | 0.20 s | 0.08 s | 0.24 s | A spark that follows its target | 26 | 6 | 7 mana |
| `SPELL_BLAST` | 0.55 s | 0.10 s | 0.40 s | An orb that bursts 2.5 m around where it strikes | 64 | 26 | 20 mana |
| `NOVA` | 0.30 s | 0.12 s | 0.45 s | A burst 4.5 m all around | 48 | 30 | 2 special points |
| `MEND` | 0.55 s | 0.15 s | 0.40 s | Light that heals | | | 2 special points |
| `QUICK_SHOT` | 0.16 s | 0.06 s | 0.20 s | An arrow | 24 | 5 | 4 stamina |
| `AIMED_SHOT` | 0.60 s | 0.06 s | 0.32 s | An arrow that passes through two more | 85 | 22 | 12 stamina |
| `VOLLEY` | 0.32 s | 0.08 s | 0.40 s | Five arrows in a fan of 50 degrees | 26 each | 6 | 2 special points |
| `LEAP_SHOT` | 0.12 s | 0.22 s | 0.36 s | An arrow, from a leap 4.2 m back | 40 | 10 | 1 special point |
| `ARROW_RAIN` | 0.40 s | 0.10 s | 0.40 s | Six arrows from the sky onto the target | 22 each | 6 | 3 special points |

A blast and an aimed shot break a piercing attack, as a heavy attack does. A mend heals the player, the companion and each raider within 8 meters by 18 percent of their health. In a raid, the heal adds to the player's threat.

## Mana

A spell spends mana, not stamina. A fighter has 100 mana, which comes back at 9 points a second. A spell that costs more mana than the fighter has does not start. The mana shows under the style's name while the player fights with magic.

## Missiles

The module is `extensions/village/missiles.mojo`. A spell or a shot sends `Missile`s from the player's hand. They fly at the locked target, or else at the nearest standing target within 26 meters and 70 degrees before the player.

| Kind | Speed | How it flies | Strikes within |
|---|---|---|---|
| `ARROW` | 42 m/s | Straight, and gravity pulls it down at 4 m/s² | 0.45 m of a chest |
| `SPARK` | 24 m/s | It turns toward its target at 5 radians a second | 0.55 m |
| `ORB` | 13 m/s | It turns at 2 radians a second, and bursts 2.5 m around | 0.7 m |

`lob` finds the speed that carries an arrow onto its target's chest. A missile strikes when its last step passes within its reach of a chest. So a fast arrow does not pass through a target between two frames. A missile ends at the ground, at the end of its life, or when it can pass through no more targets.

## Skills and the specialty

Each style has its own skill, which fighting in the style trains: see [Village skills](Village-skills#the-skills). Each level over 1 makes the style's blows 5 percent stronger. A level also teaches the style's combos: see [Village combos](Village-combos).

`BattleParameters.specialty` names the style that the player specializes in. Its blows are 10 percent stronger, and only it teaches `MASTER` combos.

## The weapons and the clips

The weapons are in `extensions/village/weapons.mojo`. Each is built along plus z from the middle of its grip, as the sword is: see [Village combat](Village-combat#the-sword-clips).

| Weapon | What it is, for a person of six feet | Where it is stowed |
|---|---|---|
| Axe | A haft of ash 75 centimeters long, and a bearded steel head with a poll | At the hip |
| Mace | A haft 60 centimeters long, wrapped in leather, and an iron head of six flanges and a spike | At the hip |
| Staff | A haft of dark wood 1.7 meters long, banded in brass, and a glowing crystal in three prongs | Across the back |
| Bow | A recurve bow 1.3 meters from tip to tip, and its string | Across the back |

The clips are in `extensions/humanoid/rig/style_clips.mojo`. Each lasts as long as the sword's move of the same button, so the style's pace plays it faster or slower.

| Clip | Seconds | What it shows |
|---|---|---|
| `fists_ready_clip` | 2.0, loops | The other foot forward, the fists up by the chin |
| `jab_clip` | 0.5 | The lead fist snapped straight out |
| `cross_clip` | 0.5 | The rear fist driven straight out, the hips turning |
| `kick_clip` | 0.77 | The rear leg chambered and kicked in an arc at the ribs |
| `haymaker_clip` | 1.09 | The rear fist cocked back, and swung over and down |
| `uppercut_clip` | 0.81 | A crouch, and the rear fist driven up |
| `spin_kick_clip` | 1.06 | A whole turn of the body with the rear leg out |
| `ground_punch_clip` | 0.65 | The rear fist raised, and driven down to the ground |
| `staff_ready_clip` | 2.0, loops | The staff upright at the side |
| `staff_bolt_clip` | 0.52 | The staff pointed at the foe, the free palm out |
| `staff_blast_clip` | 1.05 | The staff drawn back, and thrust out with both hands |
| `nova_clip` | 0.87 | The staff raised high, and driven into the ground |
| `mend_clip` | 1.1 | The staff raised high and held |
| `bow_ready_clip` | 2.0, loops | Side on, the bow low |
| `quick_shot_clip` | 0.42 | A short draw to the chin, and a loose |
| `aimed_shot_clip` | 0.98 | A long draw to the ear, held, and a loose |
| `volley_clip` | 0.8 | The bow canted, drawn, and loosed in a sweep |
| `leap_shot_clip` | 0.7 | A crouch, the legs tucked in the air, and a loose |
| `rain_clip` | 0.9 | The bow raised high, and loosed at the sky |

`Arms` plays a style's clip for each move it has one of, and the sword's clip for any other. The weapon of the style in use shows in the hand while it is drawn, and stowed while it is not. The axe, the mace and the sword use the sword's clips.

## Limits

- The ultimate is the sword's spin in each style.
- Fists and shots leave no blade's trail. A spinning kick does.
- The bow's string does not move as the arm draws it.
