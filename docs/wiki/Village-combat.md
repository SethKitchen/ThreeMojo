# Village combat

A player of the [Village walk](Village-walk) carries a sword, and can fight. A companion fights beside them. Four bandits and their captain keep a camp on the meadow. A pack of three wolves keeps a den east of the pond. Two straw dummies stand near the start for practice.

The rules are of the action games' kind. The player spends ki on each move, picks a stance, and makes artes from an arte gauge. Perfect dodges, parries, long combos and a limit gauge reward good play. The foes guard, sidestep, rage and wind up red burst attacks.

![A man in red fights hooded bandits beside a woman in blue: he cuts, spins and sends a wave, and she casts bolts of light](out/village_combat.png)

`examples/village_combat.mojo` draws this picture. A gamepad of the web backend plays a fixed script against the bandits, and the companion fights beside the player. To fight with your own gamepad or keyboard, run `examples/village_walk.mojo --play`: see [Village walk](Village-walk#play-the-game).

## The controls

| Control | Gamepad | Keyboard |
|---|---|---|
| Light attack | The right shoulder | `F` |
| Heavy attack | The north button | `G` |
| Plunge, in the air | Jump, and press the north button | Jump, and press `G` |
| Rising edge, an arte | Hold the left trigger, and press the right shoulder | `Z` |
| Tempest, an arte | Hold the left trigger, and press the north button | `X` |
| Demon fang, an arte | Hold the left trigger, and press the west button | `B` |
| Mystic arte, Over Limit | Hold the left trigger, and press the right shoulder and the north button together | `M` |
| Dodge | The east button | `C` |
| Guard | Hold the left shoulder | Hold `V` |
| Ki pulse | Press the left shoulder just after a swing | Press `V` just after a swing |
| Lock on, or let go | Press the right stick | `T` |
| Move the lock to the next target | While locked, flick the right stick left or right | While locked, press the left or the right arrow |
| Eat herbs to heal | The back button | `H` |
| The companion's boost attack | Hold the left trigger, and press the left shoulder | `Q` |
| High stance | Hold the left shoulder, and press the north button | `6` |
| Middle stance | Hold the left shoulder, and press the west button | `7` |
| Low stance | Hold the left shoulder, and press the south button | `8` |

A move starts on a new press. Hold a button and the move starts once. While the left shoulder guards, the north, the west and the south buttons choose a stance. They do not attack, use or jump then. While the left trigger is held, the west button makes the demon fang, and does not use. The east button also runs, so a dodge needs the sword drawn.

## The rules

The module is `extensions/village/combat.mojo`. A `Fighter` holds a body's health, its ki and its arte gauge, its stance, and the move it makes. It does not know where it stands. The battle finds the fighters that a swing reaches, and gives each one a blow.

### Ki

Each light attack, heavy attack and dodge spends ki. Ki comes back 0.6 seconds after the player last spent it, at 32 points a second. During a guard it comes back at half that pace.

A fighter that spends its last ki is winded. It staggers when its move ends. A blow that lands also takes ki. A fighter whose ki runs out staggers for 1.6 seconds. A blow on a staggered fighter is critical, and does 1.5 times its damage.

A heavy attack on a staggered fighter with 35 percent of its health or less is a **finisher**. It fells the fighter at once, and its word is `FINISHER`.

A **ki pulse** gets back the ki that a swing spent. Press the guard button just after the swing's active part. Within 0.15 seconds, the pulse gets back all of it. Until 0.45 seconds, it gets back half. A pulse that gets ki back also ends a winded state.

### Stances

`CombatStance` is `HIGH_STANCE`, `MID_STANCE` or `LOW_STANCE`. A stance changes the light and the heavy attacks, and the dodge. A stance changes only while the fighter makes no move.

| Stance | Damage and ki damage | Time of an attack | Ki of an attack or a dodge | Ki lost to a guarded blow | Length of a dodge |
|---|---|---|---|---|---|
| High | 1.3 times | 1.2 times | 1.3 times | 1.2 times | 0.9 times |
| Middle | 1 time | 1 time | 1 time | 0.75 times | 1 time |
| Low | 0.75 times | 0.8 times | 0.7 times | 1 time | 1.15 times |

### Artes

An arte is a strong move that spends points of the arte gauge, not ki. The gauge holds 5 points. It fills by half a point a second, and by 0.2 points for each blow that lands. The rising edge costs 2 points, and throws the foe into the air. The tempest costs 3 points. It spins the player round, and strikes all round four times.

The demon fang costs 1 point. Its cut along the ground sends a wave of force that runs 12 meters at 14 meters a second. The wave strikes each target it passes over once, for 45 damage. It shows as an arch of light across the way it runs.

### The plunge

A heavy attack in the air is a **plunge**. The player dives at 14 meters a second, and cuts down to the ground. The cut strikes everything within 2.6 meters, all round, for 70 damage. A ring of light spreads over the ground as it strikes. The plunge has armor until it strikes, and it counters a burst attack as a heavy attack does. Throw a foe up with the rising edge, jump after it, cut, and plunge to end the combo.

### The lock and the heal

The lock button locks the camera on the standing target nearest the middle of the view, within 16 meters. A radian off the middle counts as 6 meters further. While locked, the player faces the target, and the camera turns toward it. A flick of the look stick moves the lock to the target nearest in angle on that side. The lock lets go when its target falls, or goes further than 22 meters.

The heal button eats one of the herbs that the player gathered: see [Village gathering](Village-gathering). A herb heals 30 percent of the player's health. A player at full health eats nothing.

### Over Limit

A limit gauge fills as the player fights well. Each blow that lands fills 4 points of 100. A blow that breaks a ki, a guard or a burst attack fills 10 more. A parry fills 15, and a perfect dodge 20.

When the gauge is full, the player goes Over Limit for 10 seconds. The arte gauge fills, and artes cost nothing. No blow makes the player reel, and their blows do 25 percent more damage. The gauge does not fill while Over Limit lasts. Bandits and dummies never go Over Limit.

### The mystic arte

While Over Limit lasts, the player can spend what is left of it on a **mystic arte**. Press the rising edge's and the tempest's buttons together. The player raises the sword to the sky, and `MYSTIC ARTE` shows large in the middle of the frame. Then the player spins round twice. The spins strike everything within 4.5 meters six times, for 70 damage a hit. Last, the player cuts down.

No blow can hit the player through the mystic arte. The foes move at 30 percent of the time while it lasts. Over Limit ends when it starts. Without Over Limit, the same buttons make the rising edge.

### Dodges

No blow can hit a dodge from 0.02 to 0.3 seconds into it. A dodge goes the way the move stick leans, or back when the stick rests. A dodge in an attack's recovery starts at once.

A blow that reaches a dodge in its first 0.15 seconds is a **perfect dodge**. The player gets back the dodge's ki and one point of the arte gauge. Time slows the bandits to 30 percent for 0.7 seconds. The next attack within 1.2 seconds is a counter, and does twice its damage.

### Guards and parries

A guard stops a blow from within 140 degrees before the fighter. The guard loses ki in place of health. A guard whose ki runs out breaks, and the fighter staggers.

A guard raised less than 0.15 seconds before the blow parries it. The guard loses no ki. The attacker loses the blow's ki, and reels. As after a perfect dodge, the next attack within 1.2 seconds is a counter. Bandits block, and do not parry.

The heavy attack and the tempest have armor until their active part ends. A blow on them does its damage, and does not make the fighter reel.

### Burst attacks

A bandit's burst attack glows red as a warning. The bandit coils for 0.7 seconds with its sword drawn back at the hip. Then it lunges, and thrusts 2.8 meters ahead. A guard does not stop the thrust, and nor does a parry. A dodge does, and a perfect dodge of a burst is as good as any other.

The burst has armor until it strikes, so a light attack does not stop it. A heavy attack or an arte that lands in the red wind-up is a **burst counter**. The bandit loses all its ki, and staggers. The fight stops for 0.2 seconds, as for a finisher. A demon fang's wave counters a burst too, from far off.

### Combos

The three light attacks chain. A press during a move waits for the chain point: the end of the active part, and 30 percent of the recovery after it. Each blow that lands adds one to the combo. Each blow does 2 percent more damage for each blow of the combo before it, up to 25 blows. The combo ends 2.5 seconds after its last blow, or when the fighter is hit.

### The moves

`CombatMove` is a type with `is_valid`, and so are `CombatStance` and `StrikeOutcome`. A bare integer does not compile. The times are for the middle stance.

| Move | Start-up | Active | Recovery | Reach | Arc | Damage | Ki damage | Ki | Arte points |
|---|---|---|---|---|---|---|---|---|---|
| `LIGHT_ONE` | 0.14 s | 0.10 s | 0.26 s | 2.0 m | 120 degrees | 30 | 8 | 9 | |
| `LIGHT_TWO` | 0.12 s | 0.10 s | 0.28 s | 2.0 m | 120 degrees | 33 | 9 | 9 | |
| `LIGHT_THREE` | 0.20 s | 0.12 s | 0.45 s | 2.3 m | 90 degrees | 54 | 16 | 12 | |
| `HEAVY` | 0.40 s | 0.14 s | 0.55 s | 2.5 m | 80 degrees | 90 | 30 | 22 | |
| `RISING_EDGE` | 0.16 s | 0.20 s | 0.45 s | 2.1 m | 100 degrees | 66 | 18 | | 2 |
| `TEMPEST` | 0.18 s | 0.48 s | 0.40 s | 2.6 m | 360 degrees | 27, four times | 7 | | 3 |
| `DEMON_FANG` | 0.20 s | 0.10 s | 0.35 s | A wave | | 45 | 10 | | 1 |
| `MYSTIC_ARTE` | 0.50 s | 1.00 s | 0.60 s | 4.5 m | 360 degrees | 70, six times | 20 | | Over Limit |
| `PLUNGE` | 0.15 s | 0.15 s | 0.45 s | 2.6 m | 360 degrees | 70 | 25 | 18 | |
| `BITE` | 0.35 s | 0.20 s | 0.45 s | 1.4 m | 70 degrees | 40 | 12 | | |
| `BURST` | 0.70 s | 0.14 s | 0.60 s | 2.8 m | 70 degrees | 120 | 45 | 20 | |
| `CAST` | 0.35 s | 0.10 s | 0.35 s | A bolt | | 28 | 10 | | |
| `THROW` | 0.45 s | 0.10 s | 0.45 s | A knife | | 40 | 14 | | |
| `DODGE` | | 0.32 s | 0.16 s | | | | | 14 | |

An attack carries its fighter forward through its start-up and its active part. A blow pushes the fighter that it hits away. The player has 500 health and 100 ki.

### The weight of a blow

A strong blow stops the whole fight for 0.06 seconds, as action games freeze a frame on a heavy hit. It also shakes the camera by 6 centimeters, and the shake dies away. A finisher or a burst counter stops the fight for 0.2 seconds, and shakes the camera twice as far. A strong blow breaks a guard, or lands and is critical, breaks a ki or fells its fighter. A blow that lands and pushes at least 4 meters a second, or throws its fighter up, is strong too.

## The bandits

The module is `extensions/village/foes.mojo`. Three hooded bandits keep a camp about 25 meters north-west of the start. A bandit is a person with a sword, as the player is. It has 300 health and 70 ki, and its blows do 55 percent of a move's damage. Their captain, taller and in red, stands behind them. The captain has 650 health and 120 ki, and its blows do 80 percent of a move's damage.

A fourth bandit, in gray and weld yellow, throws knives. A thrower keeps 8 meters from the player, and never takes the attack token. About every 3.5 seconds, it draws its free arm back and throws a knife at the player's chest. The knife flies straight at 18 meters a second. A dodge evades it, and a guard blocks it or parries it, as it does a cut.

Below half its health, the captain rages. `RAGE` shows over it as it begins, and under its bars while it lasts. A raging fighter's attacks take 80 percent of their time. A raging bandit's dice roll high. It makes no plan of two light attacks, and twice as many burst attacks.

A `Brain` decides what a bandit does, frame by frame. `FoeState` is a type with `is_valid`.

| State | What the bandit does | It moves on when |
|---|---|---|
| `POSTED` | Stands at its post | The player comes within 14 meters: `ALERTED` |
| `ALERTED` | Faces the player for 0.7 seconds | The time is over: `CLOSING` |
| `CLOSING` | Runs or walks at the player | It is within 3.6 meters: `CIRCLING` |
| `CIRCLING` | Steps round the player, facing them | Its wait is over and it holds the attack token: `ATTACKING` |
| `ATTACKING` | Comes within 1.9 meters and makes its plan of attacks | The plan is done: `RETREATING` |
| `RETREATING` | Backs away for 0.8 seconds | The time is over: `CIRCLING` |
| `GUARDING` | Guards for 0.9 seconds | The time is over: `CIRCLING` |
| `RETURNING` | Walks back to its post | It is there: `POSTED` |

Only the bandit that holds the attack token attacks. The others wait their turn round the player. A plan is two or three light attacks, a heavy attack, or a light and a heavy attack. One plan in ten is a burst attack. A blow that lands on an attacking bandit breaks off its plan.

A waiting bandit answers about one attack of the player's in three. Two answers in five are a sidestep, and the rest are a guard. A bandit's perfect dodge does not slow the fight.

A bandit returns to its post when the player falls. It also returns when the player leads it more than 28 meters from its post. The dice that choose come from each bandit's seed, so a fight plays the same way each time.

A fallen bandit gives 8 coins, which go into the satchel. One time in two, it also drops a herb. It lies for 10 seconds, and comes back to its post after a minute.

Fighting trains the player's swordplay. Each level over 1 makes the player's blows 5 percent stronger: see [Village skills](Village-skills).

## The wolves

Three wolves keep a den about 30 meters east of the pond. A wolf is an animal of the village, meshed as a flipbook of its walk, as the herds are. It has 160 health and 60 ki, and no guard. Its one attack is the `BITE`: a crouch of 0.35 seconds, and a leap of 2.4 meters that bites. A bite does 60 percent of 40 damage.

A wolf's brain is a bandit's with a beast's temper. It notices the player from 18 meters, waits its turn 4.5 meters away, and leaps to bite from 3.2 meters. It runs at 7 meters a second. Where a bandit would guard an attack, a wolf leaps back from it. The wolves take turns with the bandits, by the same attack token.

A fallen wolf lies on its side. It gives no coins, but it trains swordplay as a bandit does. It comes back to its den after a minute.

## The companion

The module is `extensions/village/companion.mojo`. A swordswoman in woad blue starts beside the player, and fights with them. The foes do not attack her: she keeps out of their way.

Out of a fight, she follows the player. She walks to them from more than 3 meters, and runs from more than 7. In a fight, she faces the player's foe, and stands 6 meters from it, 70 degrees off the line from the foe to the player. So she keeps out of the way of the camera.

She never strays more than 10 meters from the player. She casts at the locked target. With no lock, she casts at the nearest foe that fights within 15 meters of the player.

Every 2.6 seconds, she points her sword and casts a bolt of light at a foe within 14 meters. The bolt flies at 16 meters a second, and follows its foe. It does 28 damage and 10 ki damage. When the player's health falls below 40 percent, she heals 15 percent of it. Then she waits 15 seconds before she heals again.

Her **boost gauge** fills by 4 points a second while the fight lasts, and by 10 for each bolt that lands. It holds 100. When it is full, the boost button calls for her **boost attack**: a gold bolt that does 70 damage and 50 ki damage. No guard stops it, and it counters a burst attack, as a heavy attack does.

## The dummies

Two straw dummies stand east of the start. A dummy is a post with a crossbar, a body of straw and a sack for a head. It has a fighter, so blows on it break its ki and become critical. It never falls, and it rocks on its post as it is hit.

## What the fight shows

The module is `extensions/village/battle_hud.mojo`. `draw_battle` writes these over the frame:

- **The companion's boost gauge**, in the bottom left. It says `BOOST READY` when it is full.
- **The gauges**, in the bottom right: the stance, the health, the ki, the limit gauge, and the arte gauge as a row of points. The health turns red below a quarter. Over Limit, the limit gauge turns gold, says `OVER LIMIT`, and empties as the time runs out. Through a mystic arte's start-up, its name stands large in the middle of the frame, and a gold star grows at the sword hand.
- **The combo**, such as `12 HITS`, on the right. It fades as the combo ends.
- **Each bandit's health and ki**, over its head, while it fights or is hurt. A staggered bandit shows `BREAK`, or `FINISH` when a heavy attack would finish it. A bandit that winds up a heavy attack shows a red `!`. A bandit that winds up a burst attack glows red at the chest, and the glow grows until it strikes. A raging bandit shows `RAGE` under its bars.
- **A dummy's ki**, over its head, while its ki is not full.
- **The lock's mark**: four gold dots round the locked target's chest.
- **The damage** of each blow, and its word, such as `PERFECT DODGE`, `PARRY`, `CRITICAL` or `BURST COUNTER`. They rise and fade.
- **The edges of the frame**, tinted. They turn blue while the player's perfect dodge slows the foes. They turn gold through a mystic arte, and red below a quarter of the player's health. A ki pulse rings the player's feet with blue light.

The note over the prompt names each arte as it starts, and each new stance. It says `OVER LIMIT!` when Over Limit begins, and `BOOST ATTACK!` when the companion makes one. The companion's bolts are blue stars, and her boost attack's is gold. A thrown knife is a small orange star. A blow that lands bursts in sparks.

A swing leaves a trail of light: white for the player, gold Over Limit, and orange for a bandit. A burst attack's thrust leaves a red trail. The mystic arte's spins leave a wide gold ring. A plunge rings the ground with light where it lands.

Through the active part, the trail grows from where the swing starts to where the blade is. It is brightest at the blade, and fades behind it. After the active part, it fades away in 0.15 seconds.

The game's renderer draws every surface opaque, so `draw_battle` adds the trails to the finished frame. See `extensions/village/slashes.mojo`.

The sword hangs at the hip until the fight starts. It is in the hand while a bandit within 10 meters fights, or the player fights. It goes back to the hip 6 seconds later.

## One frame of the fight

`VillageGame.tick` calls `Battle.tick` in place of the player's own step. The module is `extensions/village/battle.mojo`. `Battle.tick` does these steps:

1. **The presses.** A new press asks the player's fighter for a move. The guard button guards while held, and a new press of it makes a ki pulse.
2. **The player moves.** A free player walks, runs and jumps, at 40 percent of the stick while guarding. A locked player faces the target.
3. **An attack turns.** Through its start-up, an attack turns the player toward the locked target. With no lock, it turns toward the nearest target within 4 meters before them.
4. **The bandits and the companion think and move.** Each bandit's brain decides, and its character steps or is carried by its move. The companion's mind decides where she goes, and when she casts and heals.
5. **The blows.** In steps of at most 1/60 second, each fighter's clock runs, and each swing gives its blow to the fighters that it reaches. A strong blow stops the next frames of the fight for 0.06 seconds.
6. **The fallen.** A fallen player comes to at the start after 4 seconds. A fallen bandit lies, then comes back to its post.

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
| `fang_clip` | 0.65 | A crouch with the sword low behind, and a cut along the ground and up |
| `mystic_clip` | 2.1 | The sword raised to the sky, two whole turns of the body with the sword arm out, and a cut down |
| `cast_clip` | 0.8 | The sword raised, and pointed at the foe with the free hand beside it |
| `plunge_clip` | 0.75 | The sword raised over the head, and a cut down to the ground in a deep crouch |
| `throw_clip` | 1.0 | The free arm drawn back over the shoulder, and flung forward to throw a knife |
| `burst_clip` | 1.44 | A long coil with the sword drawn back at the hip, and a lunge that thrusts it straight ahead |
| `tempest_clip` | 1.06 | The sword arm out, and a whole turn of the body |
| `dodge_clip` | 0.48 | A low, quick crouch |
| `guard_clip` | 1.0, loops | The blade held across before the face |
| `flinch_clip` | 0.4 | The head and the chest thrown back |
| `stagger_clip` | 1.6 | Bent over, the sword low, swaying for breath |
| `fall_clip` | 2.0 | The knees give, and the body falls on its back |

The rig faces plus z, and calls the side on plus x its right. A camera behind the rig sees plus x on its own left. So the poses are written for a sword arm on plus x, and `mirrored` turns them over. The sword is in `LEFT_HAND`, the hand a player sees as the right.

## The parts

| Module | Holds |
|---|---|
| `combat.mojo` | `CombatMove`, `CombatStance`, `StrikeOutcome`, `MoveData`, `FighterParameters`, `Fighter`, `reaches` and `faces`. |
| `battle.mojo` | `BattleParameters`, `Foe`, `Ally`, `Bolt`, `Person`, `Pelt`, `Battle`, `pressed`, `push_of`, `throw_up` and `strong_blow`. |
| `foes.mojo` | `FoeState`, `Brain`, `Sight`, `Intent`, `Bandit`, `Den`, `Post` and `Dummy`. |
| `companion.mojo` | `Companion`, `AllySight`, `AllyIntent`, `ally_fighter`, `boost_blow` and `default_allies`. |
| `arms.mojo` | `Arms`: a body's swords and sword clips. |
| `blade.mojo` | `SwordLooks`, `add_sword` and `add_scabbard`. |
| `slashes.mojo` | `Trail`, `Sparks`, `draw_wave`, `glow_triangle`, `glow_ribbon`, `glow_star` and `slash_material`. |
| `battle_hud.mojo` | `draw_battle`. |
| `pad_input.mojo` | `fight_input`, and the fight's keys. |

## Limits

- The fight is not saved. A new game starts with full health, and every bandit at its post.
- A blow lands where its arc meets a fighter's circle. The blade's own path does not decide it.
- The foes do not attack the companion, and she is never hurt.
- Only the player has artes. A bandit makes light attacks, heavy attacks and burst attacks only.
- A trail is a flat ribbon, not the blade's exact path. It is added over the frame, so a wall does not hide it.
- A fighter in the air hangs there while its attack strikes. The plunge is the one attack made for the air.
