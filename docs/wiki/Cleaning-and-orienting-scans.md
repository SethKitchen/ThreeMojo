# Cleaning and orienting scans

`extensions/scan/clean.mojo`, `orient.mojo` and `place.mojo` make a scan ready to draw and to use. They leave out the splats that are not the building, find which way is up, and stand the scan in a scene in meters. All three read the splats alone. They need no frame, no model and no download.

![A scanned brick church with a lead roof, drawn from above its graveyard](out/seem-church.png)

The picture is a scan of Seem Kirke in Denmark by Peter Rødsgaard Rasmussen, under CC BY 4.0. `examples/scan_view.mojo` draws it after `clean_scan`.

| Module | What it gives |
|---|---|
| `scan/clean` | `clean_scan`, `CleanOptions`, `CleanReport`, `CleanedScan` and `splat_subset` |
| `scan/orient` | `estimate_up`, `UpEstimate` and `largest_variance` |
| `scan/place` | `scan_placement` and `ScanPlacement` |

## Clean a scan

A trained scan holds more than its subject. A drone or a video sees the sky and the far hills, and the trainer puts a few huge, faint splats there. It also leaves floaters near the camera paths. These splats cost time and hide the building. `clean_scan` leaves out three kinds, each by one rule that does not depend on the scan's frame.

| Kind | The rule |
|---|---|
| Outside | The splat's center is outside the box of the scan's body. The box holds all but `trim` of the centers at each end of each axis, and grows by `margin` of its size on each side. |
| Faint | The splat's opacity is below `min_opacity`. |
| Huge | The splat's longest axis, taken out to three standard deviations, is longer than `max_extent` of the box's diagonal. |

```mojo
var cleaned = clean_scan(scan.geometry, default_clean_options())
print(cleaned.report.kept, cleaned.report.outside, cleaned.report.faint, cleaned.report.huge)
var splats = cleaned.geometry.copy()
```

The default options suit a building. They are a trim of 0.5 percent, a margin of 15 percent, an opacity of 0.05, and an extent. The extent is 5 percent of the diagonal. A splat that breaks two rules counts for the first one: outside, then faint, then huge.

The cleaning leaves each kept splat as it was, with its harmonics. `splat_subset(geometry, kept)` copies any chosen splats of a scan into a scan of their own. `part_splats` of [Scan parts](Scan-parts) uses it too.

| Scan | Splats | Outside | Faint | Huge |
|---|---|---|---|---|
| Seem Kirke | 937,996 | 2,247 | 20,481 | 267 |

## Find the up axis

A scan keeps the axes of the software that trained it. A building has floors, and a floor or the ground is a wide, flat surface. So the flat splats vote for the up axis.

1. A splat is flat when its smallest variance is at most 0.05 of its middle one.
2. Each flat splat adds its weight, its opacity times its area, to the scan axis that its normal is nearest to.
3. The axis with most of the weight is up, or down.

The normal of a splat is the eigenvector of its covariance with the smallest eigenvalue. The module finds it by the power method.

The sign comes from the walls. A wall stands on the floor, so the weight of the splats that stand upright is on the up side of the floor's layer. The floor's layer is the heaviest layer of flat splats along the axis. `UpEstimate.side` says how plainly the walls gave the sign. It is 0 for a scan with no walls, or one with as much wall below the floor as above it. Then the sign is the one that most scans have: the y axis points down in COLMAP, so up is -y.

```mojo
var up = estimate_up(splats)
print(up.axis.name(), up.share, up.side)
```

`share` is the share of the flat splats' weight that the up coordinate holds. A third is no preference. Seem Kirke gives -y with a share of 0.57 and a side of 0.87.

## Place a scan in a scene

A scene of the renderer has y up. Its x is east and its z is south. `scan_placement(frame)` turns a [frame](Scanned-buildings#the-frame), with its heading and its origin, into the rotation, the scale and the position of one `Object3D`.

```mojo
var node = scene.add(Object3D())
scan_placement(frame).apply(scene.node(node))
scene.update()
```

The scan's splats then stand in the scene in meters, with the scan's origin at the scene's origin and its up along +y. Move the node to put the scan anywhere else. `ScanPlacement.to_scene` gives where a scan point stands.

## Limits

- The three rules of the cleaning are for a building. A scan of a landscape with a small building in it keeps its landscape. Crop it first.
- A haze or a sky made of splats that are smaller than 5 percent of the box stays in the scan. A drone scan of a village can keep large, hazy splats for this reason.
- `estimate_up` reads the splats of a scene with flat surfaces. A scan of an aerial view of terrain gives its ground as up. A scan of a room has no sign to read, unless its floor is heavier than its ceiling. Look at the picture, as `examples/scan_view.mojo` does with `auto`, before you trust the estimate.
- Most scenes on SuperSplat have up along -y, as the training code gives it. The manifest's frames use that unless a scan says otherwise.
