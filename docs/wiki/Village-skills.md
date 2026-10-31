# Village skills

A player of the [Village walk](Village-walk) has nine skills: foraging, mining and fishing, and one for each fighting style. Each thing gathered gives its skill experience, and fighting gives the experience of the style in use. A skill rises a level with enough experience, and a higher level makes gathering or fighting better.

The module is `extensions/village/skills.mojo`. `VillageGame` keeps the player's `Skills`, and gives them the experience of each thing gathered.

## The skills

`SkillKind` is a type with `is_valid`. A bare integer does not compile.

| Skill | Gathered from | Experience for each thing | What a higher level does |
|---|---|---|---|
| `FORAGING` | Herbs, mushrooms and berries | 10, 6 and 4 | From level 5, `FORAGE_BONUS_LEVEL`, each pick gives one thing more. |
| `MINING` | Ore | 30 | A boulder takes one strike fewer for each 3 levels, `MINING_STEP`. It takes 3 strikes at levels 1 to 3, 2 at levels 4 to 6, and 1 from level 7. |
| `FISHING` | Fish | 25 | A fish bites sooner. The wait is `FISH_HASTE`, 6 percent, shorter for each level over 1. |
| `SWORDPLAY` | Fighting with the sword: see [Village combat](Village-combat) | 2 for each blow that lands on a foe, 1 for each on a straw dummy, and 40 for each foe felled | The player's blows in the style are `FIGHTING_MIGHT`, 5 percent, stronger for each level over 1. Each level teaches the style's combos: see [Village combos](Village-combos). |
| `BRAWLING` | Fighting hand to hand | As swordplay | As swordplay |
| `AXEWORK` | Fighting with the axe | As swordplay | As swordplay |
| `MACEWORK` | Fighting with the mace | As swordplay | As swordplay |
| `SPELLCRAFT` | Fighting with magic | As swordplay | As swordplay |
| `MARKSMANSHIP` | Fighting with the bow | As swordplay | As swordplay |

Coins and trinkets give no experience.

## The levels

A skill begins at level 1, and stops at `MAX_LEVEL`, 10. `level_experience` gives the experience that a level needs: 25 times one less than the level, times the level.

| Level | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---|---|---|---|---|---|---|---|---|
| Experience | 50 | 150 | 300 | 500 | 750 | 1,050 | 1,400 | 1,800 | 2,250 |

When a skill rises a level, the note over the prompt says so, such as `MINING LEVEL 2!`.

## The display

The heads-up display lists each skill with experience in the top left. A line gives the name, the level, and the experience out of what the next level needs, such as `MINING 2  60/150`. A skill at level 10 shows its experience alone. See [Village gathering](Village-gathering#the-heads-up-display).

## How the game uses the levels

`Gathering` and `Battle` do not know the skills. It holds three settings, and `VillageGame` sets them from the levels before each frame:

| Setting | From | What it does |
|---|---|---|
| `ore_strikes` | `ore_strikes(level)` | How many strikes a boulder takes to give its ore |
| `forage_bonus` | `forage_bonus(level)` | How many more things a pick of herbs, mushrooms or berries gives |
| `fish_haste` | `fish_haste(level)` | The share of a fish's usual wait that it waits |

After `Gathering.update` gives something, `Skills.gain` adds its experience. `gain` returns the skill if it rose a level.

`Battle` counts each style's experience of each frame in `trained`, a list with one entry for each style. `style_skill` names the style's skill. `VillageGame` gives each entry to `Skills.train`.

Before each frame, it sets the strength of the player's blows to `fighting_might` of the level of the style in use. The player's specialty adds 10 percent. It also gives the battle each style's level, which teaches the style's combos. The fallen Stone Warden gives 400 experience: see [Village raid](Village-raid#the-loot).

## Limits

- The skills last as long as the game. They are not saved.
- A level does not change what a chest or a trinket gives.
