# Village combat

A player of the [Village walk](Village-walk) carries a sword and five more fighting styles, and can fight. A companion fights beside them. Four bandits and their captain keep a camp on the meadow. A pack of three wolves keeps a den east of the pond. Two straw dummies stand near the start for practice.

The rules are of the action games' kind. The player spends stamina on each move, picks a stance, and makes specials from a special gauge. Perfect dodges, parries, long combos and a limit gauge reward good play. The foes guard, sidestep, rage and wind up red piercing attacks.

This page gives the rules that every style shares, with the sword's moves. The other pages give the rest:

- [Village fighting styles](Village-styles): hand to hand, the axe, the mace, magic and archery, and their weapons and clips.
- [Village combos](Village-combos): strings of presses, the beat, and the combos that each level teaches.
- [Village raid](Village-raid): the Stone Warden, which a party must fight together.
- [Village walk](Village-walk#the-players-movement): the sprint, the brakes, strafing and the jump's grace.
- [Village netcode](Village-netcode): the hooks that a networking layer builds on, and a sample layer in the tests.

![A man in red fights barbarians in fur beside a ranger: he cuts, spins and sends a wave, and she casts bolts of light](out/village_combat.png)

`examples/village_combat.mojo` draws this picture. A gamepad of the web backend plays a fixed script against the bandits, and the companion fights beside the player. To fight with your own gamepad or keyboard, run `examples/village_walk.mojo --play`: see [Village walk](Village-walk#play-the-game).

## The controls

| Control | Gamepad | Keyboard |
|---|---|---|
| Light attack | The right shoulder | `F` |
| Heavy attack | The north button | `G` |
| Plunge, in the air | Jump, and press the north button | Jump, and press `G` |
| Rising edge, a special | Hold the left trigger, and press the right shoulder | `Z` |
| Whirlwind, a special | Hold the left trigger, and press the north button | `X` |
| Ground wave, a special | Hold the left trigger, and press the west button | `B` |
| Ultimate, in a surge | Hold the left trigger, and press the right shoulder and the north button together | `M` |
| Dodge | The east button | `C` |
| Guard | Hold the left shoulder | Hold `V` |
| Stamina recovery | Press the left shoulder just after a swing | Press `V` just after a swing |
| Lock on, or let go | Press the right stick | `T` |
| Move the lock to the next target | While locked, flick the right stick left or right | While locked, press the left or the right arrow |
| Eat herbs to heal | The back button | `H` |
| The companion's assist attack | Hold the left trigger, and press the left shoulder | `Q` |
| High stance | Hold the left shoulder, and press the north button | `6` |
| Middle stance | Hold the left shoulder, and press the west button | `7` |
| Low stance | Hold the left shoulder, and press the south button | `8` |

A move starts on a new press. Hold a button and the move starts once. While the left shoulder guards, the north, the west and the south buttons choose a stance. They do not attack, use or jump then. While the left trigger is held, the west button makes the ground wave, and does not use. The east button also runs, so a dodge needs the sword drawn.

Out of a fight, a tap of the east button rolls: see [Village walk](Village-walk#the-players-movement).

## The rules

The module is `extensions/village/combat.mojo`. A `Fighter` holds a body's health, its stamina and its special gauge, its stance, and the move it makes. It does not know where it stands. The battle finds the fighters that a swing reaches, and gives each one a blow.

### Stamina

Each light attack, heavy attack and dodge spends stamina. Stamina comes back 0.6 seconds after the player last spent it, at 32 points a second. During a guard it comes back at half that pace.

A fighter that spends its last stamina is winded. It staggers when its move ends. A blow that lands also takes stamina. A fighter whose stamina runs out staggers for 1.6 seconds. A blow on a staggered fighter is critical, and does 1.5 times its damage.

A heavy attack on a staggered fighter with 35 percent of its health or less is a **finisher**. It fells the fighter at once, and its word is `FINISHER`.

A **stamina recovery** gets back the stamina that a swing spent. Press the guard button just after the swing's active part. Within 0.15 seconds, the pulse gets back all of it. Until 0.45 seconds, it gets back half. A pulse that gets stamina back also ends a winded state.

### Stances

`CombatStance` is `HIGH_STANCE`, `MID_STANCE` or `LOW_STANCE`. A stance changes the light and the heavy attacks, and the dodge. A stance changes only while the fighter makes no move.

| Stance | Damage and stamina damage | Time of an attack | Stamina of an attack or a dodge | Stamina lost to a guarded blow | Length of a dodge |
|---|---|---|---|---|---|
| High | 1.3 times | 1.2 times | 1.3 times | 1.2 times | 0.9 times |
| Middle | 1 time | 1 time | 1 time | 0.75 times | 1 time |
| Low | 0.75 times | 0.8 times | 0.7 times | 1 time | 1.15 times |

### Specials

A special is a strong move that spends points of the special gauge, not stamina. The gauge holds 5 points. It fills by half a point a second, and by 0.2 points for each blow that lands. The rising edge costs 2 points, and throws the foe into the air. The whirlwind costs 3 points. It spins the player around, and strikes all around four times.

The ground wave costs 1 point. Its cut along the ground sends a wave of force that runs 12 meters at 14 meters a second. The wave strikes each target it passes over once, for 45 damage. It shows as an arch of light across the way it runs.

### The plunge

A heavy attack in the air is a **plunge**. The player dives at 14 meters a second, and cuts down to the ground. The cut strikes everything within 2.6 meters, all around, for 70 damage. A ring of light spreads over the ground as it strikes. The plunge has armor until it strikes, and it counters a piercing attack as a heavy attack does. Throw a foe up with the rising edge, jump after it, cut, and plunge to end the combo.

### The lock and the heal

The lock button locks the camera on the standing target nearest the middle of the view, within 16 meters. A radian off the middle counts as 6 meters further. While locked, the player faces the target, and the camera turns toward it. A flick of the look stick moves the lock to the target nearest in angle on that side. The lock lets go when its target falls, or goes further than 22 meters.

The heal button eats one of the herbs that the player gathered: see [Village gathering](Village-gathering). An herb heals 30 percent of the player's health. A player at full health eats nothing.

### The surge

A limit gauge fills as the player fights well. Each blow that lands fills 4 points of 100. A blow that breaks a stamina, a guard or a piercing attack fills 10 more. A parry fills 15, and a perfect dodge 20.

When the gauge is full, the player surges for 10 seconds. The special gauge fills, and specials cost nothing. No blow makes the player reel, and their blows do 25 percent more damage. The gauge does not fill while a surge lasts. Bandits and dummies never surge.

### The ultimate

While a surge lasts, the player can spend what is left of it on a **ultimate**. Press the rising edge's and the whirlwind's buttons together. The player raises the sword to the sky, and `ULTIMATE` shows large in the middle of the frame. Then the player spins around twice. The spins strike everything within 4.5 meters six times, for 70 damage a hit. Last, the player cuts down.

No blow can hit the player through the ultimate. The foes move at 30 percent of the time while it lasts. The surge ends when it starts. Without a surge, the same buttons make the rising edge.

### Dodges

No blow can hit a dodge from 0.02 to 0.3 seconds into it. A dodge goes the way the move stick leans, or back when the stick rests. A dodge in an attack's recovery starts at once.

A blow that reaches a dodge in its first 0.15 seconds is a **perfect dodge**. The player gets back the dodge's stamina and one point of the special gauge. Time slows the bandits to 30 percent for 0.7 seconds. The next attack within 1.2 seconds is a counter, and does twice its damage.

### Guards and parries

A guard stops a blow from within 140 degrees before the fighter. The guard loses stamina in place of health. A guard whose stamina runs out breaks, and the fighter staggers.

A guard raised less than 0.15 seconds before the blow parries it. The guard loses no stamina. The attacker loses the blow's stamina, and reels. As after a perfect dodge, the next attack within 1.2 seconds is a counter. Bandits block, and do not parry.

The heavy attack and the whirlwind have armor until their active part ends. A blow on them does its damage, and does not make the fighter reel.

### Piercing attacks

A bandit's piercing attack glows red as a warning. The bandit coils for 0.7 seconds with its sword drawn back at the hip. Then it lunges, and thrusts 2.8 meters ahead. A guard does not stop the thrust, and nor does a parry. A dodge does, and a perfect dodge of a piercing attack is as good as any other.

The piercing attack has armor until it strikes, so a light attack does not stop it. A heavy attack or a special that lands in the red wind-up is a **pierce break**. The bandit loses all its stamina, and staggers. The fight stops for 0.2 seconds, as for a finisher. A ground wave breaks a piercing attack too, from far off.

### Chains

The three light attacks chain. A press during a move waits for the chain point: the end of the active part, and 30 percent of the recovery after it. Each blow that lands adds one to the combo. Each blow does 2 percent more damage for each blow of the combo before it, up to 25 blows. The combo ends 2.5 seconds after its last blow, or when the fighter is hit. A string of presses can also end in a combo's finisher: see [Village combos](Village-combos).

### The moves

`CombatMove` is a type with `is_valid`, and so are `CombatStance` and `StrikeOutcome`. A bare integer does not compile. The times are for the middle stance and the sword. The spells and the shots are on [Village fighting styles](Village-styles#the-buttons-and-the-moves).

| Move | Start-up | Active | Recovery | Reach | Arc | Damage | Stamina damage | Stamina | Special points |
|---|---|---|---|---|---|---|---|---|---|
| `LIGHT_ONE` | 0.14 s | 0.10 s | 0.26 s | 2.0 m | 120 degrees | 30 | 8 | 9 | |
| `LIGHT_TWO` | 0.12 s | 0.10 s | 0.28 s | 2.0 m | 120 degrees | 33 | 9 | 9 | |
| `LIGHT_THREE` | 0.20 s | 0.12 s | 0.45 s | 2.3 m | 90 degrees | 54 | 16 | 12 | |
| `HEAVY` | 0.40 s | 0.14 s | 0.55 s | 2.5 m | 80 degrees | 90 | 30 | 22 | |
| `RISING_EDGE` | 0.16 s | 0.20 s | 0.45 s | 2.1 m | 100 degrees | 66 | 18 | | 2 |
| `WHIRLWIND` | 0.18 s | 0.48 s | 0.40 s | 2.6 m | 360 degrees | 27, four times | 7 | | 3 |
| `GROUND_WAVE` | 0.20 s | 0.10 s | 0.35 s | A wave | | 45 | 10 | | 1 |
| `ULTIMATE` | 0.50 s | 1.00 s | 0.60 s | 4.5 m | 360 degrees | 70, six times | 20 | | A surge |
| `PLUNGE` | 0.15 s | 0.15 s | 0.45 s | 2.6 m | 360 degrees | 70 | 25 | 18 | |
| `BITE` | 0.35 s | 0.20 s | 0.45 s | 1.4 m | 70 degrees | 40 | 12 | | |
| `PIERCE` | 0.70 s | 0.14 s | 0.60 s | 2.8 m | 70 degrees | 120 | 45 | 20 | |
| `CAST` | 0.35 s | 0.10 s | 0.35 s | A bolt | | 28 | 10 | | |
| `THROW` | 0.45 s | 0.10 s | 0.45 s | A knife | | 40 | 14 | | |
| `DODGE` | | 0.32 s | 0.16 s | | | | | 14 | |

An attack carries its fighter forward through its start-up and its active part. A blow pushes the fighter that it hits away. The player has 500 health and 100 stamina.

### The weight of a blow

A strong blow stops the whole fight for 0.06 seconds, as action games freeze a frame on a heavy hit. It also shakes the camera by 6 centimeters, and the shake dies away. A finisher or a pierce break stops the fight for 0.2 seconds, and shakes the camera twice as far. A strong blow breaks a guard, or lands and is critical, breaks a stamina or fells its fighter. A blow that lands and pushes at least 4 meters a second, or throws its fighter up, is strong too.

## The bandits

The module is `extensions/village/foes.mojo`. Three barbarians in fur keep a camp about 25 meters north-west of the start, each with the hair and the beard of a barbarian. A bandit is a person with a sword, as the player is. It has 300 health and 70 stamina, and its blows do 55 percent of a move's damage. Their captain, a taller warlock, stands behind them. The captain has 650 health and 120 stamina, and its blows do 80 percent of a move's damage.

A fourth bandit, in a ranger's green, throws knives. A thrower keeps 8 meters from the player, and never takes the attack token. About every 3.5 seconds, it draws its free arm back and throws a knife at the player's chest. The knife flies straight at 18 meters a second. A dodge evades it, and a guard blocks it or parries it, as it does a cut.

Below half its health, the captain rages. `RAGE` shows over it as it begins, and under its bars while it lasts. A raging fighter's attacks take 80 percent of their time. A raging bandit's dice roll high. It makes no plan of two light attacks, and twice as many piercing attacks.

A `Brain` decides what a bandit does, frame by frame. `FoeState` is a type with `is_valid`.

| State | What the bandit does | It moves on when |
|---|---|---|
| `POSTED` | Stands at its post | The player comes within 14 meters: `ALERTED` |
| `ALERTED` | Faces the player for 0.7 seconds | The time is over: `CLOSING` |
| `CLOSING` | Runs or walks at the player | It is within 3.6 meters: `CIRCLING` |
| `CIRCLING` | Steps around the player, facing them | Its wait is over and it holds the attack token: `ATTACKING` |
| `ATTACKING` | Comes within 1.9 meters and makes its plan of attacks | The plan is done: `RETREATING` |
| `RETREATING` | Backs away for 0.8 seconds | The time is over: `CIRCLING` |
| `GUARDING` | Guards for 0.9 seconds | The time is over: `CIRCLING` |
| `RETURNING` | Walks back to its post | It is there: `POSTED` |

Only the bandit that holds the attack token attacks. The others wait their turn around the player. A plan is two or three light attacks, a heavy attack, or a light and a heavy attack. One plan in ten is a piercing attack. A blow that lands on an attacking bandit breaks off its plan.

A waiting bandit answers about one attack of the player's in three. Two answers in five are a sidestep, and the rest are a guard. A bandit's perfect dodge does not slow the fight.

A bandit returns to its post when the player falls. It also returns when the player leads it more than 28 meters from its post. The dice that choose come from each bandit's seed, so a fight plays the same way each time.

A fallen bandit gives 8 coins, which go into the satchel. One time in two, it also drops an herb. It lies for 10 seconds, then goes in a cloud of dust, `VANISH_DUST`, three times a foot's, that settles in a second. `Battle.vanish_puffs` gives the dust. It comes back to its post after a minute, in a like cloud.

Fighting trains the player's swordplay. Each level over 1 makes the player's blows 5 percent stronger: see [Village skills](Village-skills).

## The wolves

Three wolves keep a den about 30 meters east of the pond. A wolf is an animal of the village, meshed as a flipbook of its walk, as the herds are. It has 160 health and 60 stamina, and no guard. Its one attack is the `BITE`: a crouch of 0.35 seconds, and a leap of 2.4 meters that bites. A bite does 60 percent of 40 damage.

A wolf's brain is a bandit's with a beast's temper. It notices the player from 18 meters, waits its turn 4.5 meters away, and leaps to bite from 3.2 meters. It runs at 7 meters a second. Where a bandit would guard an attack, a wolf leaps back from it. The wolves take turns with the bandits, by the same attack token.

A fallen wolf lies on its side. It gives no coins, but it trains swordplay as a bandit does. It comes back to its den after a minute.

## The companion

The module is `extensions/village/companion.mojo`. A swordswoman dressed as a ranger starts beside the player, and fights with them. A foe goes for her when she stands nearer it than the player by `ALLY_SHY`, 1.5 meters, or more. Struck down, she lies still until the fight round her is over, and then rises.

Out of a fight, she follows the player. She walks to them from more than 3 meters, and runs from more than 7. In a fight, she faces the player's foe, and stands 6 meters from it, 70 degrees off the line from the foe to the player. So she keeps out of the way of the camera.

When the player goes into a house and she is outside, she goes to its front door and in through it, then follows them inside. `follow_point` gives the point she walks to, and `Battle.doors` holds the houses' front doors.

The door's jambs leave her 8 centimeters each side of its axis. When she stands farther off the axis, she walks onto it at 45 degrees first. `DOOR_LANE` is that width. A wall in her way then turns her along it to the door. Indoors, she does not stop within `DOOR_CLEAR`, 1.2 meters, of the door. She walks on in, so that the raiders behind her can come in too.

When the player stands more than `CLIMB_RISE`, 1.5 meters, above her indoors, she climbs the house's stairs to them. She walks the house's way up point by point, from the foot of her own story's flight: `climb_step` gives the point. Once she climbs, she climbs on until she is within `CLIMB_REACH`, half a meter, of their height. She comes down the same way when the player stands that far below her. When the player goes out, she comes down to the foot of the stairs and out by the front door. `ally_goal` gives her goal, and `Climb` holds where she is on the stairs.

Out of a fight, a raider of the party follows the player into a house, and up and down its stairs, the same way.

Outdoors, she finds her way round the houses and the pond. `route_grid`, in `extensions/village/route.mojo`, lays a grid of 1-meter cells over the village. A cell is closed where a wall or a solid lot stands near its middle, or where the water is too deep to wade. When a house stands between her and the spot she walks to, `find_route` finds the shortest way over the open cells. `follow_route` then gives the furthest point of that way that she sees straight.

She finds her way again each second, or when her goal moves 2 meters. When no way leads to the spot, she walks straight to her goal, and looks for a way again after the same second. Indoors, the door and the stairs give her way.

Raiders on the stairs pass through each other and under the player, so a line of them does not jam a narrow flight.

The pond is too deep to wade at its middle. When her straight way to her goal passes within `POND_MARGIN`, 1 meter, of the pond's edge, she walks round it. She goes first to a point that far outside the margin, on the side of the pond nearest her way. `around_pond` gives that point, and a raider walks round the pond the same way.

She never strays more than 10 meters from the player. She casts at the locked target. With no lock, she casts at the nearest foe that fights within 15 meters of the player.

Every 2.6 seconds, she points her sword and casts a bolt of light at a foe within 14 meters. The bolt flies at 16 meters a second, and follows its foe. It does 28 damage and 10 stamina damage. When the player's health falls below 40 percent, she heals 15 percent of it. Then she waits 15 seconds before she heals again.

Her **assist gauge** fills by 4 points a second while the fight lasts, and by 10 for each bolt that lands. It holds 100. When it is full, the assist button calls for her **assist attack**: a gold bolt that does 70 damage and 50 stamina damage. No guard stops it, and it counters a piercing attack, as a heavy attack does.

## The dummies

Two straw dummies stand east of the start. A dummy is a post with a crossbar, a body of straw and a sack for a head. It has a fighter, so blows on it break its stamina and become critical. It never falls, and it rocks on its post as it is hit.

## What the fight shows

The module is `extensions/village/battle_hud.mojo`. `draw_battle` writes these over the frame:

- **The companion's assist gauge**, in the bottom left. It says `ASSIST READY` when it is full, and the words glow gold.
- **The gauges**, in the bottom right, on a panel of frosted glass. A line names the style and the stance, such as `SWORD  MID STANCE`, and gives the health as a large number, such as `478 / 500`. Under it are the health, the stamina, the mana for magic, and the limit gauge, then the special gauge as a row of points. The health turns red below a quarter, and the stamina turns amber below a quarter. The health's number turns red while what a blow took drains from the bar. In a surge, the limit gauge turns gold, says `SURGE`, and empties as the time runs out. Through an ultimate's start-up, its name stands large and leaning in the middle of the frame, and a gold star grows at the sword hand. The name lands larger and eases to its size.
- **The combo**, such as `12 HITS`, on the right: the count large and leaning, and `HITS` small. Each hit pops the count, as a blow's number pops. It fades as the combo ends.
- **The red edges.** Below `VIGNETTE_HEALTH`, 35 percent, of their health, the edges of the player's frame redden, more the nearer they are to falling. The red beats as a heart does, about 80 times a minute. A blow that lands on the player flashes them red for 0.4 seconds. `draw_vignette` draws them.
- **Each bandit's health and stamina**, over its head, while it fights or is hurt. On each health bar, the health that a blow took stays pale for `CHIP_HOLD`, 0.45 seconds. Then it drains at `CHIP_DRAIN`, 60 percent of the bar a second. So a hit shows how much it took. The player's health bar and the target panel's show it too. `Fighter.chip` holds the health that the bar shows. A staggered bandit shows `BREAK`, or `FINISH` when a heavy attack would finish it. A bandit that winds up a heavy attack shows a red `!`. A bandit that winds up a piercing attack glows red at the chest, and the glow grows until it strikes. A raging bandit shows `RAGE` under its bars. A bandit captain or a knife thrower is named over its bars, small, unless it staggers or winds up a heavy attack. Where two bars would cover each other, the nearer foe's bar keeps its place. The farther one's stands over it.
- **A dummy's stamina**, over its head, while its stamina is not full.
- **The lock's mark**: a thin gold ring of four arcs around the locked target's chest, with a gold dot at its middle. The arcs leave gaps at the top, the foot and the two sides. A dark ring lies under the gold one, so it reads over any ground. `draw_arcs` draws each ring. The ring turns red while the locked bandit winds up a heavy attack.
- **The way of each blow on the player**: a red crescent near the edge of the frame, toward where the blow came from. It is widest and strongest at its middle, and it tapers to nothing at its ends. It tells the player which way to turn. It fades in `HURT_SECONDS`, 1.2 seconds. A blow that a guard blocks takes no health, so it shows no arc. `hurt_way` gives the way on the frame.
- **The target panel**, under the compass: the locked foe's name, such as `BANDIT` or `WOLF`, and its health and stamina bars. `draw_target` writes it, and `target_name` gives the name. While a warden fights, the panel and the compass stand under the warden's bars: `hud_drop` gives how far down.
- **The damage** of each blow, and its word, such as `PERFECT DODGE`, `PARRY`, `CRITICAL` or `PIERCE BREAK`. They rise and fade. A word that shows, for less than `WORD_REPEAT`, 0.4 seconds, does not show again: a burst of critical blows says `CRITICAL` once. A dark ring surrounds each one, so it reads over the sky. A number is bold and leans, and a word stands upright. A critical blow's gold number glows: a faint gold halo, much bolder than the number, lies under it. A number is half again as large as a word, and a critical blow's gold number is twice as large. Each number appears 40 percent larger, `POP_GROW`, and eases back to its size over `POP_EASE`, 0.25 seconds: `pop_grow` gives how much. Its box stands larger for `POP_SECONDS`, 0.12 seconds. `popup_scale` gives the box's size. They stand under `TOP_BAND`, 46 dots of the font, so they do not cross the compass or the target panel. They move down together, so they keep their order. Two numbers that would cover each other stand one over the other. The newest stays by its fighter, and the older moves up. `stack_boxes` sets them. A number also moves up over a foe's bar, unless that would take it past the band. A number that newer numbers lift more than `POPUP_STACK`, three, of its own heights is not drawn. So a quick combo writes a short column, not a wall over the fighter.
- **The edges of the frame**, tinted. They turn blue while the player's perfect dodge slows the foes. They turn gold through an ultimate, and red below a quarter of the player's health. A stamina recovery rings the player's feet with blue light.

Each gauge is a bar that leans, on a dark plate. `draw_gauge` draws it. Its fill is shaded from light at its top to dark at its foot, and its leading edge is bright. A gauge `TICK_WIDTH`, 160 pixels, wide and `TICK_HEIGHT`, 5 pixels, tall or more has a mark at each tenth.

For the styles, the combos and the raid, `draw_battle` also writes:

- **The routes** of the combos that the string is on the way to, over the combo counter. Each is the combo's name, leaning, and a chip for each of its keys. A key's chip is gold once pressed, white for the next key, and dim after that. `ON BEAT` shows after a press on the beat.
- **The combo book**, while it shows.
- **The warden's bars**, at the top; **the party**, on the left; and **the zones** of the warden's attacks, in red light on the ground. See [Village raid](Village-raid#what-shows).
- **The spells and the arrows**, as stars of light.

The note over the prompt names each special as it starts, and each new stance. It says `SURGE!` when a surge begins, and `ASSIST ATTACK!` when the companion makes one. The companion's bolts are blue stars, and her assist attack's is gold. A thrown knife is a small orange star. A blow that lands bursts in sparks.

A blow that lands also flashes. A star of light opens where it struck, and a ring of light grows from it. Both fade in `IMPACT_SECONDS`, 0.22 seconds.

A plain blow's flash is a warm white, and a critical blow's, a finisher's or a pierce break's is gold and larger. A blow on the player flashes red. A blow that a guard blocks or parries gives a small blue flash, as steel strikes steel. `impact_color` and `impact_power` give the flash. `draw_impact` draws it.

The body that a blow hurts glows white for `FLASH_SECONDS`, 0.08 seconds. Each `Body` keeps a copy of each of its materials that glows, at `FLASH_STRENGTH`, 0.12. `Body.flash` puts the copies on its skin and its clothes. `Arms.pose` calls it while `Fighter.struck_lately` holds.

A swing leaves a trail of light: white for the player, gold in a surge, and orange for a bandit. A piercing attack's thrust leaves a red trail. The ultimate's spins leave a wide gold ring. A plunge rings the ground with light where it lands.

Through the active part, the trail grows from where the swing starts to where the blade is. It is brightest at the blade. Behind it, it fades as the square of the distance, so it is a bright streak with a faint wake. It is brightest along the path of the blade's tip, and faint by the hand. Near the blade, a thin white edge runs along its outer side, so the swing reads as a cut. After the active part, it fades away in 0.15 seconds.

The game's renderer draws every surface opaque, so `draw_battle` adds the trails to the finished frame. See `extensions/village/slashes.mojo`.

The sword hangs at the hip until the fight starts. It is in the hand while a bandit within 10 meters fights, or the player fights. It goes back to the hip 6 seconds later.

### How a blow feels

A blow that takes `HITSTOP_BLOW`, 40, of a foe's health or more all but stops the world for `HITSTOP`, 0.07 seconds. A foe is a bandit, a wolf or a warden. The world then moves at `HITSTOP_PACE`, 0.15, of its speed. A knock sounds as each blow lands, on a foe or on a dummy: see [Village walk](Village-walk#sound).

A strong blow shakes the camera, and narrows its field of view a moment: by `PUNCH`, 6 percent, at a finisher's shake. The view eases back as the shake dies. `Battle.foes_health` gives the health that the foes have left, all told. A hard landing and a roll kick up dust from the ground, which settles in a second.

## One frame of the fight

`VillageGame.tick` calls `Battle.tick` in place of the player's own step. The module is `extensions/village/battle.mojo`. `Battle.tick` does these steps:

1. **The presses.** A new press asks the player's fighter for a move. The guard button guards while held, and a new press of it makes a stamina recovery.
2. **The player moves.** A free player walks, runs and jumps, at 40 percent of the stick while guarding. A locked player faces the target.
3. **An attack turns.** Through its start-up, an attack turns the player toward the locked target. With no lock, it turns toward the nearest target within 4 meters before them.
4. **The bandits and the companion think and move.** Each bandit's brain decides, and its character steps or is carried by its move. The companion's mind decides where she goes, and when she casts and heals.
5. **The blows.** In steps of at most 1/60 second, each fighter's clock runs, and each swing gives its blow to the fighters that it reaches. A strong blow stops the next frames of the fight for 0.06 seconds.
6. **The fallen.** A fallen player loses `FALL_COST`, 25 percent, of the coins they carry, and comes to at the start after 4 seconds. A fallen bandit lies, then comes back to its post. Each bandit felled gives 8 coins and a seal.

`Character.drive` carries a character at a set speed over the ground. An attack's lunge, a dodge and a blow's push use it. The walls, the water and the obstacles still stop the character.

## The sword clips

The module is `extensions/humanoid/rig/sword_clips.mojo`. Each clip is worked out from key poses, as the clips of [Game humanoid](Game-humanoid) are. A clip of a move lasts as long as the move does in the middle stance. `Arms` adds the clips to a `Body`, and plays the clip of the fighter's move.

| Clip | Seconds | What it shows |
|---|---|---|
| `ready_clip` | 2.0, loops | Knees bent, the sword side forward, the sword before the body |
| `light_one_clip` | 0.5 | A cut from the sword's side across to the other side |
| `light_two_clip` | 0.5 | A backhand cut back across |
| `light_three_clip` | 0.77 | A step and a cut down from over the head |
| `heavy_clip` | 1.09 | A long wind-up high, and a lunge that cuts down across |
| `rising_edge_clip` | 0.81 | A crouch with the sword low, and a cut up that rises onto the toes |
| `ground_wave_clip` | 0.65 | A crouch with the sword low behind, and a cut along the ground and up |
| `ultimate_clip` | 2.1 | The sword raised to the sky, two whole turns of the body with the sword arm out, and a cut down |
| `cast_clip` | 0.8 | The sword raised, and pointed at the foe with the free hand beside it |
| `plunge_clip` | 0.75 | The sword raised over the head, and a cut down to the ground in a deep crouch |
| `throw_clip` | 1.0 | The free arm drawn back over the shoulder, and flung forward to throw a knife |
| `pierce_clip` | 1.44 | A long coil with the sword drawn back at the hip, and a lunge that thrusts it straight ahead |
| `whirlwind_clip` | 1.06 | The sword arm out, and a whole turn of the body |
| `dodge_clip` | 0.48 | A low, quick crouch |
| `guard_clip` | 1.0, loops | The blade held across before the face |
| `flinch_clip` | 0.4 | The head and the chest thrown back |
| `stagger_clip` | 1.6 | Bent over, the sword low, swaying for breath |
| `fall_clip` | 2.0 | The knees give, and the body falls on its back |

A fighter in a closed skirt that covers the shins, such as a robe or a gown, is hobbled. `hobbles` tells. In the hand-to-hand style, such a fighter swings the haymaker where others kick, and the uppercut where others spin and kick. A kicking leg would pass out through the front of the skirt. The moves keep their timing and their damage.

The scabbard and the sheathed sword hang back and down from the hip, on the side of the right thigh. A leg that kicks or lunges back would pass through them. So, each frame, `Arms` turns them away from that thigh, in the plane of the two, until they are `SHEATH_CLEARANCE`, 40°, apart. `sheath_turn` gives the turn.

The rig faces plus z, and calls the side on plus x its right. A camera behind the rig sees plus x on its own left. So the poses are written for a sword arm on plus x, and `mirrored` turns them over. The sword is in `LEFT_HAND`, the hand a player sees as the right.

## The parts

| Module | Holds |
|---|---|
| `combat.mojo` | `CombatMove`, `CombatStance`, `StrikeOutcome`, `FightButton`, `MoveData`, `FighterParameters`, `Fighter`, `style_move`, `reaches` and `faces`. |
| `styles.mojo` | `FightingStyle`, `StyleTraits` and `style_traits`. |
| `combos.mojo` | `ComboKey`, `ComboTier`, `Combo`, `ComboTracker`, `ComboBook`, `on_beat` and `default_combos`. |
| `missiles.mojo` | `MissileKind`, `Missile`, `fly`, `touches`, `fan`, `rain_spots` and `lob`. |
| `weapons.mojo` | `add_weapon`, and the axe's, the mace's, the staff's and the bow's triangles. |
| `boss.mojo` | `Boss`, `BossAttack`, `BossPhase`, `Zone`, `ZoneShape`, `inside` and `share_rockfall`. |
| `party.mojo` | `PartyRole`, `PartyMind`, `MemberSight`, `MemberIntent` and `escape`. |
| `raid.mojo` | `RaidParameters`, `Raider`, `Warden`, `Member`, `member_fighter`, `puppet_move` and `add_stones`. |
| `raid_hud.mojo` | `draw_raid` and `draw_zone`. |
| `netcode.mojo` | `pack_command`, `pack_snapshot`, `InputHistory`, `Relevance` and `relevance`. |
| `battle.mojo` | `BattleParameters`, `Foe`, `Ally`, `Bolt`, `Person`, `Pelt`, `Battle`, `pressed`, `push_of`, `throw_up`, `strong_blow` and `pose_person`. |
| `foes.mojo` | `FoeState`, `Brain`, `Sight`, `Intent`, `Bandit`, `Den`, `Post` and `Dummy`. |
| `companion.mojo` | `Companion`, `AllySight`, `AllyIntent`, `ally_fighter`, `assist_blow` and `default_allies`. |
| `arms.mojo` | `Arms`: a body's weapons and the clips of each style it carries. |
| `blade.mojo` | `SwordLooks`, `add_sword` and `add_scabbard`. |
| `slashes.mojo` | `Trail`, `Sparks`, `draw_wave`, `glow_triangle`, `glow_ribbon`, `glow_star` and `slash_material`. |
| `battle_hud.mojo` | `draw_battle`. |
| `pad_input.mojo` | `fight_input`, and the fight's keys. |

## Limits

- The fight is not saved. A new game starts with full health, and every bandit at its post.
- A blow lands where its arc meets a fighter's circle. The blade's own path does not decide it.
- Only the Stone Warden attacks the raiders.
- Only the player has specials. A bandit makes light attacks, heavy attacks and piercing attacks only.
- The bandits fight with the sword alone.
- A trail is a flat ribbon, not the blade's exact path. It is added over the frame, so a wall does not hide it.
- A fighter in the air hangs there while its attack strikes. The plunge is the one attack made for the air.
