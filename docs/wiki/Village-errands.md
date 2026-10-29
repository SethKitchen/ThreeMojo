# Village errands

A player of the [Village walk](Village-walk) can talk to its villagers. Some villagers give errands: they ask for things that the player gathers, and they pay coins for them. See [Village gathering](Village-gathering) for the things.

The module is `extensions/village/talk.mojo`. `VillageGame` builds a `Talk` from `PlayParameters.speakers`, and runs it in each `tick`.

## Talk to a villager

Walk to a villager. When the villager is within 2.2 meters, the prompt says `E  TALK TO` and the villager's name. Press the use button: `E` on the keyboard, or the west button of a gamepad.

The use button gathers first. It talks only when no spot is in reach.

What the villager says shows in a panel over the prompt for `SPEECH_SECONDS`, 5 seconds, after the villager's name.

The villager stops for the same time and turns to face the player. `Residents.hold` stops a person and turns them toward a point at 4 radians a second. Their route waits for them.

## Errands

A `Speaker` is a villager, a name and lines. A speaker can also have an `Errand`. An errand holds the kind of thing wanted, how many, and the coins paid. It also holds what the speaker says to ask and to thank.

`ErrandState` is a type with `is_valid`. A bare integer does not compile.

| State | The marker over the speaker's head | A word with the speaker |
|---|---|---|
| `OFFERED` | A gold `!` that turns and bobs | The speaker asks for the things. The errand is taken. |
| `TAKEN` | A silver `!` | With enough of the things in the satchel, the speaker takes them and pays. The errand is done. Without, the speaker says how many more they need. |
| `DONE` | None | The speaker says the next of their lines. |

A speaker with no errand says their lines, one after another. The markers are unlit, so they show in shade and in rain.

The heads-up display lists each errand that is taken and not done in the top right, such as `HERBS FOR MAUD 2/5`. See [Village gathering](Village-gathering#the-heads-up-display).

## The default speakers

`default_speakers` gives these speakers:

| Speaker | Villager | Errand | Reward |
|---|---|---|---|
| Maud | The woman by the brick house | Five herbs | 20 coins |
| Osric | The man on the trail | Three ore | 30 coins |
| Wren | The child by the pond | Six berries | 8 coins |
| Aldous | The old man by the framed cottage | Four mushrooms | 15 coins |
| Edith | The woman by the framed house | None | None |

A speaker whose villager is not in the village is left out. Two speakers of one villager are refused. An errand must want one thing or more, and not coins. Its reward must not be negative.

## Limits

- An errand is given once. The speaker does not give another after it is done.
