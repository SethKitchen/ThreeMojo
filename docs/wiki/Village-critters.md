# Village critters

The [Village walk](Village-walk) has small lives in its meadow. Fireflies drift and blink over the pond and the grass at night. Butterflies flutter over the meadow by day. Neither flies in rain.

The module is `extensions/village/critters.mojo`. `VillageGame` builds `Critters` from `PlayParameters.haunts`, and runs them in each `tick`.

## The critters

| Critter | What it is | When it shows | How it moves |
|---|---|---|---|
| Firefly | A mote 8 centimeters across. It is drawn unlit in yellow-green, so it glows. | The daylight is less than `NIGHT`, 0.3 | It drifts slowly, 0.4 to 1.3 meters up. It glows for `BLINK`, 55 percent, of its time. |
| Butterfly | A dark body and four wings 24 centimeters across | The daylight is more than `DAY`, 0.6 | It flutters 0.5 to 1.2 meters up, and faces the way it flies. It beats its wings at `FLAP`, 16 radians a second. |

A critter hides when the rain is more than `WET`, 0.5. The daylight comes from the [day](Village-day), and the rain from the [weather](Village-weather).

The wings take one of four colors in turn: orange, cream, blue and yellow. `wing_color` gives them.

## Set the haunts

A `Haunt` is a round patch of the meadow, and how many fireflies and butterflies keep to it. Each critter flies its own loop round a point of its haunt.

```mojo
from extensions.village.critters import Haunt
from extensions.village.play import PlayParameters
from extensions.village.quality import LOW, game_quality
from units.si import METER, Length

var parameters = PlayParameters(game_quality(LOW))
parameters.haunts.append(
    Haunt(Length(0.0, METER), Length(10.0, METER), Length(5.0, METER), 8, 2)
)
```

`Haunt.check` refuses a radius that is not from 0 to 100 meters. It refuses a count of fireflies or butterflies that is not from 0 to 64.

`default_haunts` gives four haunts. The pond has 14 fireflies and 2 butterflies. Three patches of the meadow, clear of the houses, have the rest: 26 fireflies and 9 butterflies in all.

A critter over the pond flies over its water, not over the floor of the basin.

## The cost

A firefly is one mesh of 8 triangles. A butterfly is three meshes: its body and the wings on each side. The default village adds 53 meshes. A hidden critter is not drawn, so by day the fireflies cost nothing, and by night the butterflies cost nothing.

## Limits

- A critter does not keep off the houses or the trees. Keep the haunts clear of them.
- The player cannot catch a critter.
- A firefly gives no light to the things round it.
