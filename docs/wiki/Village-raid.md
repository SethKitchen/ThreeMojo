# Village raid

The Stone Warden is a giant who keeps a ring of standing stones behind the village's start. It is too strong for one fighter: a party must fight it together. Four raiders wait at the stones, and join the player's party as the player comes near.

![A man in red fights a gray giant with a mace beside four raiders, as red zones spread on the ground before each swing](out/village_raid.png)

`examples/village_raid.mojo` draws this picture. A scripted gamepad locks on to the warden, closes in and makes combos. When a red zone holds the player, it dodges out before the zone strikes. When a rockfall marks a member, it runs to them, so they share the boulder. The fight starts with the warden's poise worn low, so it staggers soon. Then the script calls a linked strike.

## How the fight goes

The modules are `extensions/village/boss.mojo` for the rules, `extensions/village/party.mojo` for the raiders' minds, and `extensions/village/raid.mojo` for the scene. `extensions/village/battle.mojo` runs the fight.

1. The raiders wait at the stones. When the player comes within 30 meters of them, they join the party, and the note says `THE RAIDERS JOIN YOUR PARTY`. They go back when the player is further than 60 meters from them.
2. The warden stands at home until a member comes within 16 meters, or strikes it. Then it walks to its target and makes the attacks of its phase, in turn.
3. Each attack lays its zone on the ground in red light. The zone fills from its middle as the attack winds up, and strikes every member in it as the fill reaches its edge.
4. The warden goes home and heals when every member has fallen, or when the party leads it further than 45 meters from home.

## The attacks

`BossAttack` is a type with `is_valid`, and so are `ZoneShape` and `BossPhase`. A bare integer does not compile.

| Attack | Zone | Wind-up | Damage | A guard stops it | What to do |
|---|---|---|---|---|---|
| `CLEAVE` | A cone of 130 degrees, 6.5 m before the warden | 1.1 s | 180 | Yes | The tank guards; the others step out to the side |
| `SLAM` | A circle of 3.5 m on its target | 1.5 s | 260 | No | Dodge out |
| `STOMP` | A circle of 7.5 m all around the warden | 1.8 s | 150 | No | Get out of melee |
| `CHARGE` | A line 18 m long and 3 m wide at a member | 1.4 s | 220 | No | Step across the line; the warden runs along it at 16 m/s |
| `ROCKFALL` | A member is marked; the boulder falls on them after 4 s | 4 s | 640, shared | No | Everyone gathers on the marked member |
| `SUMMON` | None | 1.2 s | | | The den's wolves come |

**The rockfall** is the fight's test of the party. Its 640 damage is split evenly between each standing member within 3.5 meters of where it falls. One member alone takes all of it, and falls. Five members each take 128. A gold ring shows the boulder's reach around the marked member, with `STACK` and the seconds left.

## Poise, threat and taunts

**Poise.** Each blow's stamina damage takes the warden's poise, of 700. The poise comes back at 70 a second, 1.5 seconds after the last blow, so one fighter cannot break it alone. When it breaks, the note says `THE WARDEN STAGGERS!`. The warden staggers for 6 seconds and makes no attack. Each blow on it is critical, and does 1.5 times its damage.

**Threat.** Each member's damage adds to its threat. A tank's damage adds 3 times as much, and the player counts as a tank with the mace. Each heal adds half the health healed. The warden turns to the member with the most threat, once that member has 1.1 times the threat of its target.

**The taunt.** A taunt gives the taunter more threat than any other member, and holds the warden on it for 4 seconds. The player can taunt once every 8 seconds, within 25 meters.

| Control | Gamepad | Keyboard |
|---|---|---|
| Taunt the warden | Hold the left trigger, and press the east button | `U` |
| Call a linked strike | Stand near the staggered warden, and press the north button | `G` |
| Revive a fallen raider | Stand by them, and hold the west button | Hold `E` |

## The linked strike

A party that strikes together does more than its members can alone. Once in each stagger, the player can call a **linked strike** on the warden.

1. Break the warden's poise, so that it staggers. The bars show `HEAVY: LINKED STRIKE`.
2. Stand within 4.5 meters of the warden.
3. Press the heavy attack. The player must have the stamina for a heavy attack.

Each standing raider within 14 meters of the warden makes their heavy attack with the player. The strike does `link_damage` for the count of members who join. Each member's share is 240, and 25 percent more for each member past the first:

| Members | Damage |
|---|---|
| 1 | 240 |
| 2 | 600 |
| 3 | 1,080 |
| 4 | 1,680 |
| 5 | 2,400 |

The fight stops for 0.2 seconds, and the camera shakes. The note says `LINKED STRIKE x5!` for a party of five. Each member's share of the damage adds to their threat. The strike can fell the warden.

## The phases and the enrage

| Phase | Health | Wind-ups | Rotation |
|---|---|---|---|
| `OPENING` | Above 70 percent | As in the table | Cleave, slam, cleave, rockfall, stomp |
| `FURY` | Above 35 percent | 0.85 times | Summon, then slam, cleave, rockfall, charge, stomp, cleave |
| `LAST_STAND` | 35 percent or less | 0.7 times | Summon, then stomp, slam, rockfall, charge, cleave, stomp, slam |

After 5 minutes the warden enrages. Its attacks do 3 times their damage and wind up twice as fast. A timer at the top of the frame counts down to it.

## Scaling

The warden's health is `boss_health` for the size of its party. It is 4,500 for one member, and half of that more for each other member. So a party of five meets a warden of 13,500 health.

## The warden's clips

The warden is a person drawn 1.45 times as large, with a mace. It plays a giant's clip for each attack, from `extensions/humanoid/rig/giant_clips.mojo`. `Arms` with `giant` set plays them. `puppet_move` paces each clip, so it strikes as the attack's zone does.

| Attack | Clip | What it shows |
|---|---|---|
| `CLEAVE` | `giant_cleave_clip` | The mace drawn far back, and swept flat across the front |
| `SLAM` | `giant_slam_clip` | The mace raised in both hands over the head, and slammed down |
| `STOMP` | `giant_stomp_clip` | A knee raised high, and the foot driven down, the arms out |
| `CHARGE` | `giant_charge_clip` | A crouch, the shoulder lowered, and a lunge behind it |
| `ROCKFALL` | `giant_call_clip` | The free hand thrust at the sky, the head thrown back |
| `SUMMON` | `giant_roar_clip` | The arms spread wide, the chest out, the head back |

## The raiders

Each raider has a `PartyMind` and a role. `PartyRole` is a type with `is_valid`.

| Raider | Role | Style | Health | Where they stand | What they do |
|---|---|---|---|---|---|
| A shieldwoman in nettle green | `TANK` | The mace | 900 | 2.8 m before the warden | Taunts the warden when it fights another member; guards a cleave; strikes when it is open |
| A priest in cream | `HEALER` | Magic | 420 | 5 m behind the player, away from the warden | Mends when a member falls below 60 percent of their health, at most once each 7 seconds; else casts bolts; revives a fallen raider |
| An axeman in weld yellow | `STRIKER` | The axe | 520 | 2.6 m behind the warden | Light attacks in a chain, and a heavy attack |
| A huntress in walnut brown | `ARCHER` | Archery | 450 | 11 m off the warden's flank | Quick shots, and an aimed shot every third |

Every raider steps out of a zone as it winds up, and dodges out of it at 80 percent of its wind-up. When a rockfall marks a member, every raider gathers on them.

**Foes go for the raiders too.** Each bandit and wolf goes for the nearest of the player and the raiders who stand with them. Its blows strike that member. So the wolves that the warden summons go for the healer and the archer, and the tank must stand between. The attack token, which lets one foe at a time attack, is for the player alone.

A fallen raider lies in the fight. A member who stands within 1.6 meters of them for 2.5 seconds, holding the use button, revives them with 40 percent of their health. Out of the fight, a fallen raider stands up after 10 seconds.

## The loot

The fallen warden gives 60 coins, 3 herbs, and 400 experience to the style the player fights in. It comes back to its home after the fight's respawn time.

## What shows

`extensions/village/raid_hud.mojo` draws these parts over the frame:

- **The warden's bars**, at the top: its name, its health, its poise, its phase or `STAGGERED`, and the time to its enrage. While a linked strike is ready, `HEAVY: LINKED STRIKE` shows under them.
- **The party**, on the left: each raider's role and health, or `DOWN` and how far a revive has gone.
- **The zones and the mark**, on the ground: see above.

## In a game of many players

In a game of many players, a player stands in each raider's place, and the mind stays out of it. `Boss` holds no scene, and decides from a `BossSight` alone, so a server can run it. Its dice come from its seed, so the same fight plays the same way on each machine. See [Village netcode](Village-netcode).

## Limits

- A knife thrower throws at the player alone.
- The fight is not saved. A new game starts with the warden at full health.
