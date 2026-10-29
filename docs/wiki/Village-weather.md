# Village weather

The [Village walk](Village-walk) has weather. Clouds drift over the sky. The day can be clear, overcast, rainy or foggy. A change of weather takes some seconds, and the weather can turn by itself.

![The village from the trail, clear, overcast, in rain and in fog](out/village_weather.png)

`examples/village_weather.mojo` draws this picture. The module is `extensions/village/weather.mojo`.

## Set the weather

`PlayParameters.weather` is the weather that the game begins in. `PlayParameters.weather_cycle` makes the weather turn by itself:

```mojo
from extensions.village.play import PlayParameters
from extensions.village.quality import LOW, game_quality
from extensions.village.weather import RAIN

var parameters = PlayParameters(game_quality(LOW))
parameters.weather = RAIN
parameters.weather_cycle = True
```

During the game, `VillageGame.weather.set` turns toward a weather. In `examples/village_walk.mojo --play`, the weather turns by itself, and the keys `1` to `4` set clear, overcast, rain and fog.

## The weathers

`WeatherKind` is a type with `is_valid`. A bare integer does not compile. `weather_look` gives the look of each kind:

| Kind | Clouds | Gloom | Rain | Fog density | Sun | Sky light |
|---|---|---|---|---|---|---|
| `CLEAR` | 0.25 | 0 | 0 | 0.0008 per meter | 1 | 1 |
| `OVERCAST` | 0.85 | 0.35 | 0 | 0.002 per meter | 0.12 | 2.5 |
| `RAIN` | 1 | 0.7 | 1 | 0.005 per meter | 0.03 | 1.8 |
| `FOG` | 0.6 | 0.2 | 0 | 0.03 per meter | 0.15 | 2.4 |

- **Clouds** is the share of the sky that the drifting layer covers.
- **Gloom** is how dark the clouds are, from white to the gray of a storm.
- **Rain** is the share of `DROPS`, 700, that fall.
- **Sun** and **sky light** multiply the sun's light and every other light of the scene.

Under cloud, the sky gives more light than on a clear day, because the cloud spreads the sun's light over the sky. So the ground keeps most of its brightness, and its shadows fade. A clear sky's light is blue. As the gloom grows, it turns gray.

## One frame

The look eases toward the look of its kind. Each second, it closes all but `exp(-0.4)` of the gap. Then:

1. `Weather.update` scales the lights and sets the fog. The fog's color turns from the sky's haze toward gray as the gloom grows. `VillageGame.tick` calls it last, because the meadow's sun sets its own lights again as it fits its shadows.
2. In heavy rain, lightning flashes every 5 to 15 seconds. A flash lights the sky and the ground, and fades in about a tenth of a second.
3. The drops fall, nearer ones faster. They slide sideways as the camera turns, so the rain seems to stand in the world.
4. `Weather.cover` draws the layer of cloud over the frame's sky, before the frame is stretched. A pixel shows the sky where its depth is infinite.
5. `Weather.rain` draws each drop as a thin streak over the window's frame, after the stretch. No drop is drawn while the camera's eye is under a roof.

## The clouds

The layer of cloud is a plane 1,500 meters up. Each sky pixel looks along its direction to the plane. The point there gives the cloud's thickness, `cloud_cover`:

1. Four octaves of value noise are added. Each octave is turned about 37 degrees against the last, so no edge lines up with the noise's lattice.
2. The sum is cut at the share that leaves the look's clouds covered, and softened over a third of its range.

The layer drifts with the wind. It fades out toward the horizon. Where the clouds cover more than half the sky, a veil of the clouds' gray covers the whole sky too. In thick fog, the sky fades into the fog's color.

The thickness is found on a grid of `CLOUD_STEP`, 4, pixels and mixed bilinearly between the points. So the clouds cost a few operations a pixel.

## Limits

- The clouds do not cast shadows, and they do not hide the sun's disk in the sky cube.
- The rain does not wet the ground or ripple the pond.
- The drops are drawn on the window. From outside, rain falls in front of a house's open door too.
