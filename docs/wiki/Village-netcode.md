# Village netcode

The fight's messages for a game of many players: a player's commands, the snapshots of the fighters, and which fighters each player hears of. The server's rules decide every blow. Each player sends only what they press.

The module is `extensions/village/netcode.mojo`. It packs and unpacks bytes. It sends nothing itself: a game sends the bytes by its own sockets.

## The tick

The server runs the fight at `TICK_RATE`, 30 ticks a second. Each tick, it runs `Battle.tick` for each region with each player's command, and sends each player the snapshots they hear of. The fight's rules have no clock but the ticks, and the foes' and the warden's dice come from their seeds. So the same commands at the same ticks give the same fight on the same machine.

## Commands

`pack_command` packs a player's command for a tick into 12 bytes:

| Bytes | What they hold |
|---|---|
| 4 | The tick, lowest byte first |
| 4 | The buttons, one bit a button, in the order of `buttons_of` |
| 4 | The move stick's forward and right, and the look stick's right and up, one byte each |

A stick's lean is kept in 255 steps: `axis_byte` gives 0 for -1, 127 at rest, and 254 for 1. `unpack_command` gives back the tick and the input, each stick within half a step of the one packed.

A message can be lost. `InputHistory` keeps each command a player sent until the server says it has it. `InputHistory.send` keeps a tick's command and gives every command kept, oldest first, for one message. `InputHistory.ack` forgets each command up to a tick. It keeps the last 64 at most.

## Snapshots

`snapshot_of` gives a `FighterSnapshot` of a character and its fighter. `pack_snapshot` packs it into 20 bytes:

| Part | Bytes | Kept as |
|---|---|---|
| The fighter's id | 2 | A whole number, to 65,535 |
| Where its feet are | 6 | Centimeters, to 327 meters from the middle |
| Its heading | 2 | A turn in 65,536 steps |
| Its health | 2 | A whole point |
| Its stamina and its mana | 2 | A share of its most, in 255 steps |
| Its special gauge | 1 | A fiftieth of a point |
| Its move | 1 | The move's value |
| Its clock in the move | 2 | Milliseconds |
| Its stance and its style | 1 | Two bits and three bits |
| Its combo | 1 | Up to 255 blows |

`unpack_snapshot` gives the snapshot back, each value within half a step. It refuses a move, a stance or a style that is not one. `apply_snapshot` sets a client's copy of a character and its fighter from a snapshot.

## Interest

A player does not hear of every fighter every tick. `relevance` says how often by how far the fighter is:

| Distance | `Relevance` | Heard |
|---|---|---|
| To 30 m | `EVERY_TICK` | Each tick |
| To 80 m | `EVERY_THIRD` | Every third tick |
| To 160 m | `EVERY_TENTH` | Every tenth tick |
| Further | `UNHEARD` | Never |

`heard` says whether a player hears of a fighter at a tick. A fighter heard less often is heard at a tick of its own, by its id. So the far fighters spread over the ticks, and no tick carries them all.

## What it costs

A player's commands cost 360 bytes a second. A snapshot costs 20 bytes. So 40 fighters near a player, heard each tick, cost 24 kilobytes a second, before the headers of the messages.

## Limits

- A client does not predict its own moves. It shows what the server sends.
- A snapshot carries no foe's brain, no missile and no popup. The client shows the missiles from the moves that send them.
- The module has no sockets, no encryption and no lag measure.
