# Village day and night

The [Village walk](Village-walk) has an hour of the day. The light fades and reddens at dusk. At night the moon lights the village, stars show, and the houses' windows glow. The hour can stay still, or pass.

![The village at five in the afternoon and at sunset, and the brick house at eleven at night, outside and in its hall](out/village_day.png)

`examples/village_day.mojo` draws this picture. The module is `extensions/village/day.mojo`.

## Set the hour

`PlayParameters.day` is a `DayCycle`: the hour the game begins at, and how many hours pass in a second.

```mojo
from extensions.village.day import DayCycle
from extensions.village.play import PlayParameters
from extensions.village.quality import LOW, game_quality

var parameters = PlayParameters(game_quality(LOW))
parameters.day = DayCycle(18, 24.0 / 1200.0)
```

The default is two in the afternoon, and it stays so. The meadow's sun was baked for that hour. In `examples/village_walk.mojo --play`, a day passes in twenty minutes, and the key `5` moves the day on three hours.

## The light

`DayCycle.daylight` is the share of the day's light. It is one from `SUNRISE`, 6:00, to `SUNSET`, 19:30, and zero at night. It changes smoothly over `TWILIGHT`, one hour, either side of each. `DayCycle.dusk` is one at sunrise and sunset, and zero 1.5 hours either side.

`DayCycle.light` scales and tints the scene's lights after the weather has set them. See [Village weather](Village-weather).

| Light | By day | At dusk | At night |
|---|---|---|---|
| The sun, a directional light | Whole | Orange | The moon: `MOON`, 0.15, of the sun's light, and blue |
| The sky, every other light | Whole | Whole | `MOONLIGHT`, 0.5, of its light, and blue |
| The sky, with the camera under a roof | Whole | Whole | Whole, and warm: the lamps and the fire light the room |
| The fog's color | As the weather sets it | Darker | 12 percent of the weather's |

The sun's direction and its shadows do not change with the hour.

## The sky

`DayCycle.night_sky` changes each sky pixel of the frame, after the weather's clouds:

1. At dusk, the sky low over the horizon turns orange.
2. Toward night, the sky turns to the deep blue `NIGHT_SKY`.
3. Once the twilight has mostly gone, stars show where the clouds leave the sky clear. A star stands in a cell of the sky's direction, so it stays fixed as the camera turns. It fades into the haze near the horizon.

The pond's water is shaded by its own sun and sky. `dim_water` darkens the pixels that the water was composed into, by `water_light`: one by day, and `MOON` at night. It multiplies each color by the square of that share, and adds `NIGHT_WATER` for the rest. So at night the pond mirrors the deep blue of the sky.

## The houses

From dusk to dawn, while `daylight` is less than a half, each house shows its `lit` node and hides its `daylit` node. See [Village houses](Village-houses).

| Node | Holds | Shows |
|---|---|---|
| `lit` | Lamplight in each window of a dwelling, seen from outside, and the night in each pane, seen from inside | From dusk to dawn |
| `daylit` | The day in each pane, seen from inside | By day |

The lamplight, the lanterns by the doors and the fire are drawn unlit, so they glow at night.

## Limits

- The sun does not move, and its shadows keep their afternoon direction.
- A lamp lights its room only by the baked light of its vertices. A lantern outside does not light the ground.
- The clouds are not lit by the moon.
