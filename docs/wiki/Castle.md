# Castle

`extensions/castle/` builds a moated brick castle from a plan. It draws the castle with brick, slate, water, lawn and woods under the sun of a date and an hour. The extension ships the plan of Wijnendale Castle at Torhout in West Flanders, Belgium. Each figure of a plan says how it was found. The page [Castle analysis](Castle-analysis) holds the engineering checks that read the same plan. The page [Landscape](Landscape) stands the castle in mountains and woods, with a scanned church beside it.

![Wijnendale Castle from the air in autumn: red brick towers and wings with slate spires, a moat, a bridge and woods](out/wijnendale.png)

The picture comes from `examples/wijnendale.mojo`. It takes about half a minute on 24 CPU threads. The sun is where it stands over Torhout at 15:00 local time on 19 October 2026. The moat is Clearwater's water, and the castle and the wood are reflected in it. The same castle is a scan of 3.65 million splats in [Virtual scans](Virtual-scans). That scan draws in milliseconds and can be walked through.

```bash
.venv/bin/mojo run -I . examples/wijnendale.mojo out/wijnendale.png
```

## Modules

| Module | What it gives |
|---|---|
| `castle/kinds` | `Material`, `RoofKind` and `Provenance`, each a type with `is_valid` |
| `castle/plan` | `CastlePlan`, `Tower`, `Wing`, `Gate`, `QuayWall`, `Moat`, `Bridge` and the point and band tools |
| `castle/wijnendale` | `wijnendale_plan`, the survey's footprint and the castle's place |
| `castle/masonry` | `Masonry` and `historic_brick`, the strength and stiffness of brickwork by EN 1996-1-1 |
| `castle/parts` | Walls with windows cut through them, plinths, crowns, dormers and spires, as triangles |
| `castle/render` | `castle_meshes`: the mesh view of a plan, one mesh for each material |
| `castle/textures` | Maps of brick, stone and slate from the real sizes of a unit |
| `castle/look` | `castle_look`: a physically based material for each surface |
| `castle/trees` | Trees grown from a branch skeleton, with cards of leaves, and shrubs |
| `castle/scene` | `build_castle_scene`, `aim_sun` and `draw_castle` |
| `castle/sky`, `reflect` | The sky and its clouds, and the mirror image in the water |
| `castle/sun`, `shadow` | The sun over a site, and the shadows of the towers; see [Castle analysis](Castle-analysis) |
| `castle/landscape`, `landscape_mesh` | The ground from the castle's meadow to the mountains, and its triangles; see [Landscape](Landscape) |
| `castle/forest`, `crowns` | The woods of a landscape by altitude and distance, and the crowns of far trees; see [Landscape](Landscape) |

## The plan

A plan is in a flat frame in meters, x east and y north of an origin that the plan names. Levels are meters above a datum. Every length is a `Length64`, every angle an `Angle64`, and every part carries a `Provenance` that says how its dimensions were found.

| Part | What it is |
|---|---|
| `Tower` | A round tower with a wall to a height and a roof over it: a spire or a crown |
| `Wing` | A band of constant width along an axis, with a gable roof whose ridge follows it. Its corners are mitered |
| `Gate` | A rectangular block with a flat top, at a heading |
| `QuayWall` | The wall that holds the island's earth at the edge of the moat |
| `Moat` | The water: an outline, a level and a depth |
| `Bridge` | A run of semicircular brick arches on piers |

`CastlePlan.check` refuses a plan whose parts do not stand together. `footprint_overlap` says how well the solids reproduce the outline that a survey gave: the area they share over the area they cover together.

`Provenance` is one of four kinds. A plan that relies on a figure can tell a survey from a guess.

| Provenance | Meaning |
|---|---|
| `SURVEYED` | From a survey: the outline of the building and of the moat |
| `MEASURED` | Fitted to survey data: a wing, the gate and a tower |
| `DOCUMENTED` | From a document |
| `ESTIMATED` | A guess from a photograph or from the style: the depth of the moat, the quay wall, the bridge's arches, the proportions of the roofs |

## Wijnendale

The Flemish heritage inventory (record 87491) and the history of the castle give the facts.

- About 1276 to 1278: Count Guy of Dampierre has a stone castle built. It is round and moated, with eleven half-round towers and a heavy gate tower.
- From 1833: the Matthieu family rebuilds the castle.
- 1877 to 1878: the Brussels architect Felix Laureys builds the pseudo-medieval gate tower with its crenellations. He extends the right wing with a round donjon.
- 1982: the castle becomes a protected monument.

The inventory gives no dimensions. The plan comes from open data of Digitaal Vlaanderen. See THIRD-PARTY-NOTICES.md.

- The outline of the building and the outline of the moat are from the Flemish large scale reference map, GRB. The building has 99 corners. The coordinates are Belgian Lambert 72. The moat outline is simplified by 0.25 m.
- The heights are from the Digital Height Model of Flanders II. It is a 1 m raster of the surface and the terrain from an airborne laser scan. The water surface is the flat 34.31 m that the scan returns over the moat.
- The towers are circles fitted to the arcs of the surveyed outline. The wings and the gate are the bands and the rectangle that best cover it. They reproduce 96 percent of the surveyed area.

The plan holds these parts: the donjon and seven turrets, the north and the south wing, the gate tower, the moat and the bridge. It also holds the low wall of the courtyard with its four quay towers.

## The mesh view

`castle_meshes(plan, default_view())` gives one geometry for each material: brick, stone, slate, water, lawn, gravel, foliage, glass, wood, metal and bark. A wall is a plate with the openings cut through it, so a window has a reveal as deep as the wall is thick. A window has a stone surround, a sill, a frame, a mullion and a pane set back in the opening. A round wall is a ring of plates, and a crown is a ring of corbels under a parapet of merlons. A wing has dormers, chimneys and a leaded ridge. The ground is a grid of heights: the bed of the moat, its banks, the island and the meadow.

The textures are procedural, and use the real sizes of a unit:

- A brick is 210 by 65 mm with a 10 mm joint, in running bond.
- A block of stone is 600 by 300 mm.
- A slate is 300 by 400 mm, laid with a 120 mm exposure.

The normals come from a height field that the same pattern makes. So a joint is a groove, and a slate has an edge that throws a shadow. `castle_look` gives each surface a metallic-roughness material.

## The scene

```mojo
var plan = wijnendale_plan()
var renderer = castle_renderer(800, 1000)
var castle = build_castle_scene(plan, default_settings(), eye_east, eye_north, 45.0)
aim_sun(castle, renderer, toward_the_sun)      # a unit vector, y up and z south
var image = draw_castle(castle, renderer, camera, 0.55, 5)
```

A picture is made in four steps.

1. The renderer draws the scene with the sky as a prefiltered environment, and soft shadows from a lamp that stands where the sun does.
2. The sky and its cumulus are painted where the renderer drew only the clear ground.
3. The water of the moat is Clearwater's, composed into the picture where it is nearest.
4. The castle and the wood are reflected in the water, in the share that Fresnel's law gives.

`aim_sun` redirects the lamp and prefilters the sky again. A low sun is dimmer and redder, because its light crosses more of the air. The woods are an illustration: the survey does not say where the trees are. They follow the photograph, a meadow open to the north, broadleaf trees close to the moat and dark conifers behind. No tree stands within a radius that the caller gives of a place, such as the camera.

`SceneSettings` trades quality for time. It sets the size of a tile of material, of the sky's cube and of the shadow map. It also sets whether the woods are grown, and the spacing of the ground grid. `default_settings()` gives 512 texel tiles, a 128 texel sky, a 4096 texel shadow map, woods and a 1 m grid.

## Limits

- The plan has no interiors. A wall is a plate and the inside is not modeled.
- The openings are a regular pattern of the style, not a survey of the windows.
- A figure that is `ESTIMATED` is a guess. The roofs' proportions, the plinth, the depth of the moat, the quay wall and the bridge's arches come from a photograph.
- The renderer draws in software, with supersampling and a shadow map. A picture takes about half a minute. To walk through the castle, draw its [scan](Virtual-scans) instead.
