# Village weather

The [Village walk](Village-walk) has weather. Clouds drift over the sky. The day can be clear, overcast, rainy, foggy or snowy. A change of weather takes some seconds, and the weather can turn by itself.

![The village from the trail, clear, overcast, in rain, in fog and in snow, and at a misty dawn](out/village_weather.png)

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

During the game, `VillageGame.weather.set` turns toward a weather. In `examples/village_walk.mojo --play`, the weather turns by itself, and the keys `1` to `4` set clear, overcast, rain and fog. The key `9` sets snow.

## The weathers

`WeatherKind` is a type with `is_valid`. A bare integer does not compile. `weather_look` gives the look of each kind:

| Kind | Clouds | Gloom | Rain | Fog density | Sun | Sky light | Snow |
|---|---|---|---|---|---|---|---|
| `CLEAR` | 0.25 | 0 | 0 | 0.0008 per meter | 1 | 1 | 0 |
| `OVERCAST` | 0.85 | 0.35 | 0 | 0.002 per meter | 0.12 | 2.5 | 0 |
| `RAIN` | 1 | 0.7 | 1 | 0.005 per meter | 0.03 | 1.8 | 0 |
| `FOG` | 0.6 | 0.2 | 0 | 0.03 per meter | 0.15 | 2.4 | 0 |
| `SNOW` | 0.9 | 0.25 | 0 | 0.004 per meter | 0.3 | 2.6 | 1 |

- **Clouds** is the share of the sky that the drifting layer covers.
- **Gloom** is how dark the clouds are, from white to the gray of a storm.
- **Rain** is the share of `DROPS`, 700, that fall.
- **Snow** is the share of `DROPS` that fall as snowflakes. A flake falls at `FLAKE_PACE`, 0.18, of a drop's pace, and drifts from side to side.
- **Sun** and **sky light** multiply the sun's light and every other light of the scene.

Under cloud, the sky gives more light than on a clear day, because the cloud spreads the sun's light over the sky. So the ground keeps most of its brightness, and its shadows fade. A clear sky's light is blue. As the gloom grows, it turns gray.

## One frame

The look eases toward the look of its kind. Each second, it closes all but `exp(-0.4)` of the gap. Then:

1. `Weather.update` scales the lights and sets the fog. The fog's color turns from the sky's haze toward gray as the gloom grows. `VillageGame.tick` calls it last, because the meadow's sun sets its own lights again as it fits its shadows.
2. In heavy rain, lightning flashes every 5 to 15 seconds. A flash lights the sky and the ground, and fades in about a tenth of a second.
3. The drops fall, nearer ones faster. They slide sideways as the camera turns, so the rain seems to stand in the world.
4. `Weather.cover` draws the layer of cloud over the frame's sky, before the frame is stretched. A pixel shows the sky where its depth is infinite.
5. `Weather.rain` draws each drop as a thin streak over the window's frame, after the stretch, and each flake as a small square. No drop or flake is drawn while the camera's eye is under a roof.

## Wet and white

`Weather.wet` is how wet the village is. A downpour soaks it over `SOAK_SECONDS`, 40 seconds, and it dries over `DRY_SECONDS`, 150 seconds. `Weather.snowed` is how much snow lies on it. A snowfall covers it over `SNOW_SECONDS`, 90 seconds, and it thaws over `MELT_SECONDS`, 240 seconds.

Each frame, `Village.weather_surfaces` sets the materials of the walls, the wood, the stone, the roofs, the grass and the ground:

1. A soaked surface keeps 70 percent of its light: `1 - SOAKED`.
2. Snow shines on the roofs, the grass and the ground as an emissive white, `SNOW_WHITE`. Its strength is `SNOW_SHINE`, 0.4, times the snow's cover, times the day's light. So snow dims at night.

## The air

`VillageGame.veil` finishes the frame's air before the stretch. See `extensions/village/air.mojo`:

1. **Ground mist.** `ground_mist` veils each pixel by how low and how far its point is. The mist thins to a third over `MIST_HEIGHT`, 2.5 meters, above the pond's water. It comes in over distance, to two thirds at `MIST_NEAR`, 25 meters. It lies in the fog's color. Fog thickens it, and it lies on the ground at dawn, thickest at 6:30.
2. **Bloom.** `bloom` blurs the light brighter than a threshold, over a frame a quarter of the size, and adds it back. By day only the brightest light glows. At night the threshold is lower and the glow stronger, so the lamps and the windows glow into the dark.

Both share the frame's rows over every core. They decode each byte by a table and encode it by `SrgbBytes`, so they give the same bytes as a power each way. On four cores, the bloom of a bright 640 by 360 frame takes 2.6 milliseconds, and the mist 2.3. A pixel at a time, they took 46 and 28.

## The clouds

The layer of cloud is a plane 1,500 meters up. Each sky pixel looks along its direction to the plane. The point there gives the cloud's thickness, `cloud_cover`:

1. Four octaves of value noise are added. Each octave is turned about 37 degrees against the last, so no edge lines up with the noise's lattice.
2. The sum is cut at the share that leaves the look's clouds covered, and softened over a third of its range.

The layer drifts with the wind. It fades out toward the horizon. Where the clouds cover more than half the sky, a veil of the clouds' gray covers the whole sky too. In thick fog, the sky fades into the fog's color.

The thickness is found on a grid of `CLOUD_STEP`, 4, pixels and mixed bilinearly between the points. So the clouds cost a few operations a pixel.

## Limits

- The clouds do not cast shadows, and they do not hide the sun's disk in the sky cube.
- The rain darkens the surfaces evenly. It leaves no puddles, and the ground does not shine. It rings the pond: see [Village](Village#the-basin-and-the-ripples).
- Snow whitens what it covers by an emissive light. It does not build up in drifts, and the leaves keep their green.
- On a GPU that draws the passes after the triangles, the frame has no ground mist and no bloom.
- The drops are drawn on the window. `VillageGame.sheltered` keeps them off each pixel whose point stands under a roof, so no rain falls in an open doorway. A `FloorIndex` sorts the houses' floors into cells of 2 meters, so a pixel tests only the floors over its point. The rows are shared over every core. A rainy 1080p frame at `LOW` takes about 28 milliseconds, as a dry one does. Before, it tested every floor for every pixel, and took 220. On a GPU that draws the passes after the triangles, the rain is not kept off a doorway.
