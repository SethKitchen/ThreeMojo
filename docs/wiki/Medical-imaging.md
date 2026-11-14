# Medical imaging

`extensions/imaging/` reads grayscale DICOM images and stacks them into volumes with physical spacing. It draws a volume with a ray caster, and it draws slices with labels and measurements. It is a library for research and teaching. It is not a medical device. Do not use it to diagnose, monitor or treat a patient.

![A cut head phantom, composited and as an isosurface, and one labeled axial slice with a measurement](out/medical-imaging.png)

`examples/medical_imaging.mojo` makes this picture. It cuts a head phantom into DICOM slices and writes each slice as a Part 10 file in memory. It then reads the files back and stacks them.

The left panel is the ray cast volume, cut in half. The middle panel is the same cut as an isosurface at 0.27. The right panel is the middle axial slice. The skull, the left ventricle and the largest feature are labeled, and a yellow line measures the head.

## Modules

| Module | What it gives |
|---|---|
| `ids` | `TransferSyntax`, `Photometric`, `PixelRepresentation`, `SliceAxis`, `RenderMode`, `SlabMode`, `Connectivity` and `LabelId` |
| `image_volume` | `ImageVolume`, a scalar grid with spacing, origin and axes, and `MILLIMETER64` |
| `dicom` | `parse_dicom`, `read_dicom`, `parse_dicom_frames` and `read_dicom_frames`, which give `DicomSlice` values, and `decode_rle_frame` |
| `dicom_write` | `DicomWriter`, `encode_dicom`, `encode_dicom_frames`, `encode_rle_frame`, `pack_bits` and `ds_text` |
| `series` | `stack_slices` and `volume_slices` |
| `nifti` | `parse_nifti`, `read_nifti`, `encode_nifti`, `encode_nifti_labels` and `labels_from_volume` |
| `phantom` | `shepp_logan`, a head of ten ellipsoids |
| `transfer` | `WindowLevel`, `TransferFunction` and `Rgba` |
| `raycast` | `VolumeCamera`, `orbit_camera`, `ray_box` and `render_volume` |
| `labels` | `LabelMap`, `threshold`, `region_grow`, `keep_largest`, `label_pieces`, `LabelPieces` and `label_surface` |
| `measure` | `label_statistics`, `voxel_distance`, `line_profile`, `LineProfile` and `full_width_half_maximum` |
| `shape` | `label_shape`, `LabelShape` and `slice_areas` |
| `compare` | `compare_labels`, `LabelComparison`, `surface_voxels` and `percentile` |
| `roi` | `circle_statistics` and `RegionStatistics` |
| `histogram` | `Histogram`, `volume_histogram`, `label_histogram` and `otsu_threshold` |
| `filter` | `gaussian_filter`, `gaussian_kernel` and `median_filter` |
| `thickness` | `label_distance`, `local_thickness`, `thickness_statistics`, `ThicknessStatistics` and `seed_distances` |
| `morphology` | `dilate_label`, `erode_label`, `open_label` and `close_label` |
| `smooth` | `weld_surface`, `smooth_surface`, `surface_area` and `enclosed_volume` |
| `printing` | `printable_stl` and `label_stl` |
| `overlay` | `render_slice`, `overlay_labels`, `draw_measurement` and `label_color` |
| `reformat` | `oblique_slice`, `slab_projection` and `sample_point` |
| `curved` | `curved_reformat` |
| `resample` | `resample_volume` and `resample_labels` |

## Read a DICOM series

Read each file of the series. Then stack the slices. The order of the files does not matter.

```mojo
var slices = List[DicomSlice]()
for path in paths:
    slices.append(read_dicom(path))
var volume = stack_slices(slices)
print(volume.nx, volume.ny, volume.nz, volume.spacing_z.to(MILLIMETER64))
```

`parse_dicom(bytes)` reads the bytes of a file that is already in memory.

## Read a multi-frame file

An enhanced CT or MR file holds every slice as a frame. Read all of its frames, and stack them:

```mojo
var volume = stack_slices(read_dicom_frames(path))
```

`read_dicom_frames(path)` and `parse_dicom_frames(bytes)` give one `DicomSlice` per frame, in file order. A file of one frame gives one slice, so these functions read every file that `read_dicom` reads. `read_dicom` refuses a file of more than one frame.

A frame takes its placement from the functional groups. The reader looks for each element in the frame's item of the per-frame functional groups (5200,9230) first. Then it looks in the shared functional groups (5200,9229), and then in the data set itself. The elements that it finds so are the pixel spacing, the slice thickness, the image position and orientation, the rescale and the window. It opens these sequences in the groups:

| Tag | Sequence | Elements |
|---|---|---|
| (0028,9110) | Pixel Measures | Pixel Spacing, Slice Thickness |
| (0020,9113) | Plane Position (Patient) | Image Position (Patient) |
| (0020,9116) | Plane Orientation (Patient) | Image Orientation (Patient) |
| (0028,9145) | Pixel Value Transformation | Rescale Intercept, Rescale Slope |
| (0028,9132) | Frame VOI LUT | Window Center, Window Width |

Native frames follow each other in the pixel data. An RLE Lossless file holds one fragment per frame. `encode_dicom_frames(frames)` writes an enhanced CT image. Each frame gets its own item of the per-frame groups, and the frames must share their layout, bits and transfer syntax.

## What the reader takes

A Part 10 file starts with a preamble of 128 bytes and the letters `DICM`. The file meta group follows in explicit VR little endian. Its transfer syntax UID gives the encoding of the data set.

The reader takes these four transfer syntaxes:

| Transfer syntax | UID | `TransferSyntax` |
|---|---|---|
| Explicit VR little endian | `1.2.840.10008.1.2.1` | `EXPLICIT_LITTLE` |
| Implicit VR little endian | `1.2.840.10008.1.2` | `IMPLICIT_LITTLE` |
| Deflated explicit VR little endian | `1.2.840.10008.1.2.1.99` | `DEFLATED_EXPLICIT` |
| RLE Lossless | `1.2.840.10008.1.2.5` | `RLE_LOSSLESS` |

The reader refuses big endian, JPEG, JPEG 2000 and every other compressed syntax. Convert such a file to one of the four first.

A deflated file holds the whole data set as one raw DEFLATE stream after the meta group. The reader expands it to at most 1 GiB, and then reads it as explicit VR little endian.

An RLE Lossless file holds encapsulated pixel data. The element holds an offset table item, then the fragments of the frame, then a sequence delimiter. The frame starts with a header of 64 bytes: the number of segments and the offset of each. Each segment holds one byte of each sample, the most significant byte first, in PackBits code. `decode_rle_frame(frame, count, step)` decodes one frame into little-endian samples. The reader refuses encapsulated pixel data in any other syntax.

The reader keeps the elements in the table. It steps over every other element. It steps over sequences of undefined length, and items of undefined length in them.

| Tag | Element | Field |
|---|---|---|
| (0008,0060) | Modality | `modality` |
| (0018,0050) | Slice Thickness | `thickness` |
| (0020,0013) | Instance Number | `instance_number` |
| (0020,0032) | Image Position (Patient) | `position`, `has_position` |
| (0020,0037) | Image Orientation (Patient) | `row_direction`, `column_direction`, `has_orientation` |
| (0028,0002) | Samples per Pixel | Must be 1 |
| (0028,0004) | Photometric Interpretation | `photometric` |
| (0028,0008) | Number of Frames | 1 for `read_dicom`, up to 65535 for `read_dicom_frames` |
| (0028,0010) | Rows | `rows` |
| (0028,0011) | Columns | `columns` |
| (0028,0030) | Pixel Spacing | `row_spacing`, `column_spacing`, `has_spacing` |
| (0028,0100) | Bits Allocated | `bits_allocated`, 8 or 16 |
| (0028,0101) | Bits Stored | `bits_stored` |
| (0028,0103) | Pixel Representation | `representation` |
| (0028,1050) | Window Center | `window_center` |
| (0028,1051) | Window Width | `window_width` |
| (0028,1052) | Rescale Intercept | `intercept` |
| (0028,1053) | Rescale Slope | `slope` |
| (7FE0,0010) | Pixel Data | `values` |

Each value in `values` is `slope * stored + intercept`. For CT, this gives Hounsfield units. The reader masks each stored value to its stored bits. It extends the sign when the pixel representation is signed.

Lengths are in meters inside the library. DICOM gives them in millimeters. Use `MILLIMETER64` to read them back in millimeters. It has a `Float64` scale, so a length keeps every digit.

## Read and write NIfTI files

Research imaging tools exchange volumes and segmentations as NIfTI-1 files. `read_nifti(path)` reads a `.nii` file or a `.nii.gz` file into an `ImageVolume`.

```mojo
var volume = read_nifti("brain.nii.gz")
var mask = labels_from_volume(read_nifti("brain_mask.nii.gz"))
Path("tumor.nii.gz").write_bytes(encode_nifti_labels(labels, volume, True))
```

The reader takes a single file in either byte order. It takes these datatypes: unsigned and signed integers of 8, 16 and 32 bits, and floats of 32 and 64 bits. It reads the first volume of a file with more than three dimensions. Each value is `scl_slope * stored + scl_inter`, and a slope of zero means no scaling.

The placement comes from the first of these that the file sets:

| Source | When |
|---|---|
| The sform rows | `sform_code` is above zero |
| The qform quaternion, with `pixdim[0]` as the flip of k | `qform_code` is above zero |
| The voxel sizes alone, method 1 of the standard | Neither code is set |

The spatial unit can be meters, millimeters or microns. A file with no unit is in millimeters. NIfTI's world is RAS: x to the right, y to the front and z up. The volume keeps the LPS patient space of DICOM, so x and y change sign. The display range `cal_min` to `cal_max` gives the window when it is a range.

`encode_nifti(volume, compress)` writes 32-bit floats. `encode_nifti_labels(map, volume, compress)` writes unsigned bytes with the label intent, 1002, so a viewer shows the values as labels. Both write the placement as sform rows in millimeters, and `compress` wraps the file in gzip. `labels_from_volume` turns a volume of whole values from 0 to 255 into a label map.

## Stack slices

`stack_slices(slices)` sorts the slices along the normal of their plane. The normal is the cross product of the row direction and the column direction. The first sorted slice gives the origin of the volume.

The slices must agree on these properties:

- Each slice has a position, an orientation and a pixel spacing.
- The slices have one size, one pixel spacing and one orientation.
- The gaps between the slices are equal, within one percent.
- No slice has a sideways shift from the line of the normal. A gantry tilt gives such a shift.

The gap between the slices becomes `spacing_z`. A single slice uses its thickness, or the column spacing when it has no thickness. The window comes from the first sorted slice that has one. A stack without a window fits its window to its values.

`volume_slices(volume, slope, intercept)` cuts a volume into one slice for each `k`. `encode_dicom(slice)` writes a slice as a Part 10 CT image in explicit or implicit VR little endian. A 16-bit file stores `round((value - intercept) / slope)`. A slope of 0.001 keeps three decimal places.

## Resample to a new spacing

CT slices are often thicker than their pixels are wide. A voxel mesh, a thickness map and a morphology ball work best on cubic voxels. Resample the volume and its labels first:

```mojo
var mm = Length64(0.5, MILLIMETER64)
var cubic = resample_volume(volume, mm, mm, mm)
var labels = resample_labels(map, mm, mm, mm)
```

The new grid keeps the first voxel center, the axes, the window and the extent of the old grid. Along each axis it has `floor(extent / spacing) + 1` voxels, so a step that does not divide the extent stops at the last whole step. `resample_volume` takes the trilinear blend of the old voxels at each new voxel center. `resample_labels` takes the label of the nearest old voxel center, because labels cannot blend.

## The volume grid

Voxel `(i, j, k)` has its center at `i * spacing_x` along `axis_x`, `j * spacing_y` along `axis_y` and `k * spacing_z` along `axis_z`, from `origin`. The values are stored with `i` fastest, then `j`, then `k`.

| Index | DICOM meaning |
|---|---|
| `i` | The column, along the row direction |
| `j` | The row, along the column direction |
| `k` | The slice, along the normal |

`trilinear(x, y, z)` blends the eight voxels around a point in voxel units. A point outside the voxel centers takes the value at the nearest edge.

## The head phantom

`shepp_logan(size, field, samples)` gives a cube of `size` voxels on each side. It holds the modified three-dimensional Shepp-Logan head. Its ten ellipsoids are the skull at 1, the brain at 0.2, two ventricles at 0 and six small features at 0.3 or 0.4.

Each voxel is the mean of `samples` cubed points in the voxel. An edge that cuts a voxel then gives a value between its two sides. This is the partial volume effect of a scanner, and it removes the stair steps from a render.

The phantom turns each ellipsoid about z only, by the angle of the two-dimensional phantom. It does not represent a real tissue, scanner or patient.

## Draw a volume

`render_volume` casts one ray through each pixel and returns a `Framebuffer`.

```mojo
var transfer = TransferFunction()
transfer.add_point(0.0, Rgba(0, 0, 0, 0))
transfer.add_point(0.3, Rgba(0.9, 0.2, 0.1, 0.7))
transfer.add_point(1.0, Rgba(1, 1, 1, 0.9))
var camera = orbit_camera(volume, Angle64(35, DEGREE64),
    Angle64(25, DEGREE64), Angle64(30, DEGREE64), 400, 400)
var image = render_volume(volume, camera, transfer, COMPOSITE, 0.5, 0.3,
    Rgba(0, 0, 0, 1), v3(0, 0.5, 0), v3(1, 1, 1))
```

The rays are in the volume frame. Voxel `(i, j, k)` has its center at `(i * spacing_x, j * spacing_y, k * spacing_z)` meters. The box of the volume reaches half a voxel past the outer centers.

| Mode | What a pixel shows |
|---|---|
| `COMPOSITE` | The transfer function's colors, blended from front to back |
| `MAXIMUM_INTENSITY` | The largest sample on the ray, through the volume's window |
| `ISOSURFACE` | The shaded surface where the ray first reaches `iso_value` |

A `TransferFunction` holds control points. Each point is a value with a color and an opacity. A value between two points blends them in a straight line. The opacity of a point is for a step of one voxel. The ray caster corrects it for the real step: a step of `s` voxels gives `1 - (1 - opacity)^s`.

`COMPOSITE` shades each sample by the gradient of the values. The light is at the eye. The `ambient` argument is the light a sample gets when it faces away. An ambient light of one turns the shading off. A ray stops when it is 99 percent opaque.

`ISOSURFACE` stops at the first sample at or above `iso_value`. The crossing lies on the straight line between that sample and the one before it. The surface takes the transfer function's color at the iso value, opaque, and the gradient shades it. A ray that enters the box at or above the iso value stops at its first sample, so a crop shows the cut face.

```mojo
var bone = render_volume(volume, camera, transfer, ISOSURFACE, 0.5, 0.25,
    Rgba(0, 0, 0, 1), iso_value=0.6)
```

`crop_low` and `crop_high` keep part of the box. Each is a fraction of the box on each axis. Use `v3(0, 0.5, 0)` and `v3(1, 1, 1)` to cut away the half of the volume with `j` below the middle.

The rows of the image are split among CPU tasks. Each pixel depends only on its own ray, so the image does not change with the number of tasks.

## Windows

`WindowLevel(center, width)` is the `LINEAR_EXACT` function of DICOM PS3.3 C.11.2.1.3.2. A value at or below `center - width / 2` is black. A value above `center + width / 2` is white. The values between rise in a straight line.

This function takes any positive width. The phantom's values run from 0 to 1, so its window has a width of 0.5. The `LINEAR` function of the standard needs a width of at least one.

## Label a volume

A `LabelMap` holds one label for each voxel of a volume. Label zero is the background. A label is a `LabelId` from 0 to 255.

| Function | What it labels |
|---|---|
| `threshold(volume, low, high, label)` | Each voxel with a value from `low` to `high` |
| `region_grow(volume, i, j, k, low, high, label)` | Each voxel in the range that connects to the seed |
| `keep_largest(map, label)` | Only the largest connected piece of the label |

By default two voxels connect when they share a face. Of two pieces of one size, `keep_largest` keeps the piece with the lowest voxel index.

The three functions that connect voxels take a `Connectivity` as their last argument:

| Connectivity | Neighbors of a voxel |
|---|---|
| `FACES`, the default | The 6 that share a face |
| `EDGES` | Also the 12 that share an edge, 18 in all |
| `CORNERS` | Also the 8 that share a corner, 26 in all |

A thin vessel that runs at a slant through the grid holds together only with `EDGES` or `CORNERS`. scipy's `ndimage.label` calls these the structures of rank 1, 2 and 3.

```mojo
var vessel = keep_largest(map, LabelId(1), CORNERS)
var grown = region_grow(volume, i, j, k, 150, 600, LabelId(2), CORNERS)
```

`label_pieces(map, label)` numbers every connected piece of a label by size, to count the lesions or stones of a segmentation. Its `map` gives label 1 to the largest piece, 2 to the next, and on up to 255. Its `sizes` and `volumes` list every piece from the largest, also past the 255th.

## Filter a volume

Filter a noisy volume before you label it. A threshold of a noisy volume gives labels with holes and stray voxels.

```mojo
var quiet = median_filter(volume, 1)
var smooth = gaussian_filter(quiet, Length64(0.8, MILLIMETER64))
```

`median_filter(volume, radius)` gives each voxel the median of the cube around it. The cube reaches `radius` voxels on each side, from 1 to 3. A median removes single noisy voxels and keeps the edges between regions.

`gaussian_filter(volume, sigma)` blurs with a Gaussian whose standard deviation is a length. The spacing of each axis turns it into voxels, so a volume with thick slices gets a narrower kernel along `k`. The filter runs one pass along each axis. Each kernel stops at three standard deviations, and its weights sum to one. `gaussian_kernel(sigma_voxels)` gives the weights.

At the edge of the grid, both filters take the value of the nearest voxel inside it. Both give a volume on the same grid, with the same placement and window.

## Clean a label

A threshold leaves small faults in a label: specks, thin bridges and holes. Clean them with a ball whose radius is a length.

```mojo
var clean = close_label(open_label(map, LabelId(1), Length64(1, MILLIMETER64)),
    LabelId(1), Length64(1, MILLIMETER64))
```

| Function | What it does |
|---|---|
| `dilate_label(map, label, radius)` | Gives the label to each background voxel within `radius` of the label |
| `erode_label(map, label, radius)` | Takes the label from each of its voxels within `radius` of a voxel outside it |
| `open_label(map, label, radius)` | Erodes, then dilates: removes specks and bridges narrower than the ball |
| `close_label(map, label, radius)` | Dilates, then erodes: fills holes and gaps narrower than the ball |

The distances are exact and center to center, with the spacing of each axis. So a volume of thick slices gets a ball of the right shape. Dilation grows into the background only, and other labels do not change. Erosion counts the grid's edge as outside, so a label also shrinks from the edge. Closing does not, so a closed label keeps every voxel of the label before it.

`seed_distances(map, seeds, border_is_seed)` gives the distance of each voxel to the nearest voxel of a mask, as a `Length64`. Both the morphology and the thickness map use it.

## Find a threshold

Use Otsu's method when the values have no fixed scale, as in MR. `otsu_threshold(histogram)` gives the bin edge that splits the voxels into two classes with the largest variance between them. This is the edge with the smallest variance within the classes.

```mojo
var span = volume.value_range()
var counts = volume_histogram(volume, 256, Float64(span[0]), Float64(span[1]))
var edge = otsu_threshold(counts)
var bright = threshold(volume, edge, Float64(span[1]), LabelId(1))
```

`volume_histogram(volume, bins, low, high)` counts the values in bins of equal width. `label_histogram(volume, map, label, bins, low, high)` counts only the voxels of one label. A value outside the range is not counted, and the value `high` goes in the last bin.

Otsu's method moves the edge into the class with the wider spread. For two classes of very different spread, check the edge against the histogram.

`label_surface(map, label)` returns the boundary of a label as a closed triangle mesh. The mesh is in the volume frame, in meters. The surface passes halfway between a voxel inside the label and a voxel outside it.

## Smooth a label surface

A label surface has steps of one voxel. Smooth it before you draw it or measure its area.

```mojo
var steps = label_surface(map, LabelId(1))
var smooth = smooth_surface(steps, 20)
print(surface_area(smooth).to(SQUARE_METER), enclosed_volume(smooth).to(CUBIC_METER))
```

`smooth_surface(geometry, passes, shrink, inflate)` first welds the mesh. Then it applies Taubin's lambda-mu filter. Each pass moves each vertex toward the mean of its neighbors by `shrink`, and then away from it by `inflate`. The defaults are 0.5 and -0.53. The filter removes the steps and keeps nearly all of the volume. A plain Laplacian filter shrinks the mesh at each pass.

`weld_surface(geometry)` only welds. Corners at the same position become one vertex, and a triangle without area is dropped. Both functions give an indexed mesh with area-weighted normals. [From CT slices to stresses](Tetrahedral-FEM#from-ct-slices-to-stresses) smooths two label surfaces and meshes the same labels for a stress analysis.

`surface_area(geometry)` gives an `Area64`. `enclosed_volume(geometry)` gives a `Volume64` from the divergence theorem. It is exact for a closed mesh whose faces turn outward. A label surface has outward faces.

## Print a label

Write a label as an STL file to print a model of it. A printed model is for teaching and for planning research. It is not a medical device.

```mojo
Path("label.stl").write_bytes(label_stl(map, LabelId(1), 20))
```

`label_stl(map, label, passes)` makes the label surface and smooths it with `passes` Taubin passes. Then it writes a binary STL file. An STL file has no unit, and slicers read it in millimeters. The library keeps lengths in meters. `label_stl` scales the surface by 1000, so the model prints at its true size.

`printable_stl(geometry)` writes any mesh in meters as a binary STL file in millimeters. Use it for a surface that you made or changed yourself.

## Measure

`label_statistics(map, volume, label)` gives the size, place and values of one label:

| Field | What it holds |
|---|---|
| `voxels` | The voxel count |
| `volume` | The voxel count times the volume of one voxel, a `Volume64` |
| `centroid` | The mean voxel center in the volume frame, in meters |
| `low_i` to `high_k` | The bounding box of the label, in voxel indexes |
| `mean`, `minimum`, `maximum` | The values of the volume inside the label |

The volume of a label is a count of voxels. It is not the volume inside a smooth surface. A small or thin region can differ from its true volume by several percent.

`voxel_distance(volume, a, b)` gives the length between two points in voxel units. It uses the spacing of each axis.

`line_profile(volume, start, end, samples, outside)` samples a volume at evenly spaced points along a line in patient space. Each point has its distance from the start and its trilinear value. A point outside the box of voxel centers takes the `outside` value.

```mojo
var profile = line_profile(volume, across_start, across_end, 200, -1000)
var diameter = full_width_half_maximum(profile, -1000)
```

`full_width_half_maximum(profile, baseline)` gives the width of the highest peak at half its height above the baseline. It is the usual measure of the diameter of a vessel with contrast, and of how sharp an image is. Each side runs to the first place where the profile falls to the half level, by linear interpolation between points. A profile that does not fall to the half level on both sides is refused.

## Measure a circle on a slice

`circle_statistics(volume, axis, index, x, y, radius)` gives the values inside a circle on one slice. A reader measures a region this way, such as the CT number of a lesion or the noise in a uniform region.

```mojo
var roi = circle_statistics(volume, K_AXIS, 40, 128.0, 96.5, Length64(5.0, MILLIMETER64))
print(roi.mean, roi.deviation, roi.pixels, roi.area.to(SQUARE_METER))
```

A pixel counts when its center is at most `radius` from the center of the circle. The center is in the pixel coordinates of the slice, as `render_slice` draws it, and it can be between pixels. The radius is a length, so a circle on pixels that are not square covers an ellipse of pixels. The grid's edge cuts a circle that reaches past it.

A `RegionStatistics` holds the pixel count, the `area`, the `mean`, the `deviation`, the `minimum` and the `maximum`. The values are in the units of the volume, such as HU after the rescale. The deviation is the sample one, with `n - 1`, as ImageJ reports it.

## Measure the shape of a label

`label_shape(map, volume, label)` gives the principal axes of a label and its equivalent ellipsoid. The axes show how an organ lies. Their lengths show whether it is round, flat or long.

```mojo
var shape = label_shape(map, volume, LabelId(1))
for k in range(3):
    print(shape.axes[k].x, shape.axes[k].y, shape.axes[k].z, shape.semi_axis(k).to(METER))
var areas = slice_areas(map, LabelId(1), K_AXIS)
```

The equivalent ellipsoid is the solid ellipsoid with the same second moments as the label. A solid ellipsoid with a semi-axis `a` has the variance `a^2 / 5` along it. So each semi-axis is `sqrt(5 lambda)`, where `lambda` is an eigenvalue of the covariance of the label. Each voxel counts as a small box, so a box label has the exact moments of a box.

A `LabelShape` holds the voxel count, the `volume`, the `center` in patient space, the three `axes` in patient space and their `semi_axes`. The longest axis is first. The sign of an axis is arbitrary.

`slice_areas(map, label, axis)` gives the area of a label in each slice across a grid axis, as `Area64` values. Use it for the cross-section of a vessel or an airway from slice to slice. A slice without the label has zero.

## Compare two segmentations

A study that segments a structure two ways must say how well they agree. Examples are a reader and a threshold, or two readers. `compare_labels(first, first_label, second, second_label)` gives the measures that segmentation studies report.

```mojo
var c = compare_labels(manual, LabelId(1), automatic, LabelId(1))
print(c.dice, c.jaccard, c.hausdorff_95.to(METER), c.mean_surface_distance.to(METER))
```

| Field | What it holds |
|---|---|
| `dice` | Twice the shared voxels over the sum of the two counts, from 0 for no overlap to 1 for the same voxels |
| `jaccard` | The shared voxels over the voxels of either label |
| `hausdorff` | The largest distance from a surface voxel of one label to the surface of the other |
| `hausdorff_95` | The 95th percentile of the surface distances of both labels together |
| `mean_surface_distance` | The mean of the surface distances of both labels, the ASSD |
| `first_voxels`, `second_voxels`, `shared_voxels` | The voxel counts |
| `first_volume`, `second_volume` | The volumes, as `Volume64` values |

The surface of a label is each voxel with a face neighbor outside the label, or on the grid's edge. `surface_voxels(map, mask)` gives it. Each surface voxel has a distance to the nearest surface voxel of the other label. The distance is center to center, with the spacing of each axis, and exact.

The percentile has linear interpolation between ranks, as numpy's default. These are the definitions of the MedPy library. Some tools take the larger of the two directed 95th percentiles instead, which is never less.

The two maps can be one map, to compare two of its labels. They must have the same grid and spacing.

## Measure thickness

Bone research measures the thickness of cortical walls and of trabeculae. `local_thickness(map, label)` gives each voxel of a label the diameter of the largest sphere that holds the voxel and fits in the label. This is the method of Hildebrand and Rüegsegger.

```mojo
var thickness = local_thickness(map, LabelId(1))
var stats = thickness_statistics(thickness, map, LabelId(1))
print(stats.mean.to(MILLIMETER64), stats.maximum.to(MILLIMETER64))
var image = render_slice(thickness, K_AXIS, 40)
```

A sphere fits when its radius is the distance from its center to the nearest voxel outside the label. `label_distance(map, label)` gives that distance, center to center, for each voxel. The transform is exact: it is the method of Felzenszwalb and Huttenlocher, with the spacing of each axis in its pass. The grid counts as surrounded by voxels outside every label.

Only the spheres that no neighbor's sphere holds can be the largest, so only they are drawn. Both maps are volumes on the grid of the label map, in millimeters, with 0 outside the label. A slab of `n` voxels is `n` voxels thick. A thin wall of one or two voxels is measured coarsely, so use voxels several times smaller than the wall.

## Draw a slice

`render_slice(volume, axis, index)` shows one slice through the volume's window, one pixel for each voxel. A `MONOCHROME1` volume shows inverted.

| Axis | Pixel x | Pixel y | Size |
|---|---|---|---|
| `K_AXIS` | `i` | `j` | `nx` by `ny` |
| `J_AXIS` | `i` | `k` | `nx` by `nz` |
| `I_AXIS` | `j` | `k` | `ny` by `nz` |

In an axial series, `K_AXIS` gives axial slices, `J_AXIS` coronal slices and `I_AXIS` sagittal slices.

## Reformat on any plane

`oblique_slice(volume, center, right, down, width, height, spacing, outside)` samples a volume on any plane through a point in patient space. Use it for a plane along a vessel or square to a bone. The directions `right` and `down` must be square to each other.

```mojo
var plane = oblique_slice(volume, center, v3(1, 1, 0), v3(0, 0, -1),
    256, 256, Length64(0.5, MILLIMETER64), -1000)
var image = render_slice(plane, K_AXIS, 0)
```

Each pixel is a trilinear sample of the volume. A point outside the box of voxel centers takes the `outside` value, such as -1000 for air in CT. The result is a volume of one slice, placed on the plane, with the source's window and photometric interpretation. `voxel_point(p)` gives the voxel units of a patient-space point. It is the inverse of `patient_point`. `sample_point(volume, p, outside)` gives the trilinear value at one point in patient space.

## Straighten a curved structure

A vessel, an airway or a spine bends through the volume, so no plane holds all of it. `curved_reformat(volume, path, up, half_height, spacing, outside)` follows a path of points in patient space, such as a centerline. It shows the whole structure in one straightened image.

```mojo
var image = curved_reformat(volume, centerline, v3(0, 0, 1), 40,
    Length64(0.5, MILLIMETER64), -1000)
var picture = render_slice(image, K_AXIS, 0)
```

Column `x` lies at the arc length `x * spacing` along the path. The path runs along the middle row, and `half_height` rows lie on each side. At each point, the lateral direction is `up` with its part along the path taken away. Row 0 is the farthest along it, so `up` points up in the image.

The lateral direction changes at each corner of the path. A path of many short segments gives a smooth image. The result keeps the window of the source. It is not a plane in patient space, so its origin is zero and its axes are those of the grid.

## Project a thick slab

A thin reformat cuts a vessel or an airway into short pieces. A thick slab projects several planes onto one, so a long structure shows whole.

```mojo
var vessels = slab_projection(volume, center, v3(1, 0, 0), v3(0, 1, 0),
    256, 256, Length64(0.5, MILLIMETER64), Length64(10, MILLIMETER64), 20,
    SLAB_MAXIMUM, -1000)
```

`slab_projection(volume, center, right, down, width, height, spacing, thickness, samples, mode, outside)` samples `samples` planes across the thickness. The planes are evenly spaced along the normal `right x down`, and centered on `center`. Each pixel keeps one value of its samples:

| `SlabMode` | Value | Use |
|---|---|---|
| `SLAB_MAXIMUM` | The largest sample | Vessels with contrast, bone |
| `SLAB_MINIMUM` | The least sample | Airways and other air |
| `SLAB_MEAN` | The mean of the samples | A thicker slice with less noise |

A point outside the volume takes the `outside` value, and that value counts in the projection. The result is a one-slice volume on the center plane, as `oblique_slice` gives it. Use at least one plane per voxel of the volume across the thickness, or a thin vessel can fall between two planes.

## Overlays

`overlay_labels(image, map, axis, index, opacity)` blends a color over each labeled pixel. The labels cycle through eight colors from `label_color`. `draw_measurement(image, axis, a, b, color)` draws the line between two points, with a small cross at each end.

## Verification

The tests check these results:

- A slice written by `encode_dicom` reads back with every element equal, in each of the four transfer syntaxes.
- Two enhanced CT files of three frames that pydicom 3.0.1 wrote, native and RLE, read with pydicom's values. Each frame takes its position and window from its own groups, and its rescale, spacing and orientation from the shared groups.
- A volume written as a multi-frame file in each of the four transfer syntaxes reads back the same. pydicom reads the native and the RLE files. That check is not part of the test suite.
- Three files that pydicom 3.0.1 wrote read with pydicom's values. They are 16-bit signed RLE, 8-bit RLE and deflated. `assets/dicom/make_dicom.py` makes them.
- `pack_bits` splits runs and literals at 128 bytes, and its code decodes to the same bytes.
- A 12-bit signed value masks and extends its sign: `0xF800` reads as -2048.
- A volume cut into slices, written, read and stacked gives the same values and spacing.
- `trilinear` is exact for a linear field.
- An oblique reformat of a linear field matches the field at every pixel.
- A curved reformat along a straight path matches a linear field at every pixel. Along a bent path, the corner falls at its arc length, and an `up` that leans along the path keeps only its square part. A point past the volume takes the `outside` value.
- A linear field resampled from 0.5 x 0.5 x 3 mm voxels to 1 mm cubes keeps its value at every new voxel. A label slice of 3 mm becomes the three 1 mm slices nearest to it.
- A slab of four planes through a ramp gives its top plane as its maximum and its bottom plane as its minimum. Its mean is its center value.
- A uniform volume of opacity 0.25 per voxel, four voxels deep, passes `0.75^4` of the background.
- An isosurface of a linear ramp has the full iso color along the gradient, and the ambient light across it.
- An ellipsoid of 904.8 voxels labels 879 voxels, within four percent, with its centroid exact.
- A Gaussian keeps a linear ramp away from the edges. Its response to one voxel is the product of its three kernels, and sums to one.
- A median removes a hot and a cold voxel and keeps the edge between two regions.
- On two overlapping distributions, the Otsu edge is the edge with the least variance within the classes, found by brute force over the voxels.
- Two voxels that share an edge are one piece with `EDGES` and `CORNERS`, and two with `FACES`. Two that share a corner only are one piece with `CORNERS`. A diagonal line grows from its end with `CORNERS`, and not with `FACES`. On a random grid of 30 by 28 by 26 voxels, the pieces of each connectivity match scipy's `ndimage.label` in count and size. That check is not part of the test suite.
- Cubes of 27 and 8 voxels and two single voxels number 1 to 4. A voxel that touches a cube at a corner only is a piece of its own.
- A Gaussian blob of sigma 2 mm has a full width at half maximum of `2 sqrt(2 ln 2) sigma`, within 1 percent. A box 5 voxels wide is exactly 5 mm wide.
- A circle of 2 pixels holds the 13 lattice points of its disc. On a ramp, a disc gives the value at its center and the sample deviation of its pixels. With pixels 0.5 mm wide, a circle of 1 mm holds 7 pixels. A circle at a corner keeps the 6 pixels of the grid.
- A box of 10 by 6 by 8 mm has voxels of 1 by 1 by 2 mm. Its semi-axes are `sqrt(5 / 12)` times its sides, to 1e-9, along the grid axes. Its axes follow the patient frame of the volume. An ellipsoid of 20, 12 and 8 mm turned 30 degrees gives its semi-axes within 2 percent, and its long axis within one degree. Each slice of the box has its area exactly.
- A label against itself has a Dice coefficient of 1 and no surface distance. Two boxes that overlap by half have a Dice of 0.5 and a Jaccard of 1/3. Their Hausdorff distance is their shift, and their HD95 and ASSD match a search of every pair. Two ellipsoids in voxels of 0.7, 0.9 and 1.5 mm match MedPy 0.5 to 1e-7 mm in every measure. That check is not part of the test suite.
- A voxel dilated by 2 mm becomes the 33 lattice points of the ball, and 15 with slices 2 mm apart. A cube of 7 voxels eroded by 1 mm is a cube of 5. Opening removes a spike, and closing fills a hole.
- The distance to the edge of an irregular label on an anisotropic grid matches a brute-force search. A slab six voxels thick is six voxels thick. With 2 mm slices and 0.5 mm pixels, a label is limited by its narrower side.
- The welded surface of a voxel ball is closed and of genus zero: `V - E + F = 2`.
- Twenty Taubin passes on that ball cut the spread of the radius by more than a third. The volume stays within 2 percent.
- A welded box of 2 m has 8 vertices, an area of 24 m^2 and a volume of 8 m^3.
- A box of 20 x 30 x 40 mm written as STL reads back with 12 triangles and its sides in millimeters. A smoothed label cube reads back with the bounds and the volume of its surface, scaled to millimeters.
- One render with one, three and every core gives the same bytes.
- Four NIfTI files that nibabel 5.3.2 wrote read with nibabel's world points and values. They cover both byte orders, the sform, the qform with a flip, voxel sizes in microns, and gzip. `assets/nifti/make_nifti.py` makes them.
- A volume and a label map written as NIfTI, plain and in gzip, read back with the same values and placement.

The example labels the left ventricle of a 128-voxel phantom. It measures 77.9 mL. The ellipsoid of the ventricle holds 76.9 mL.

## Errors

Every function raises `Error` for input it cannot use. The table gives the cases.

| Case | Functions |
|---|---|
| A file is not Part 10, or ends inside an element | `parse_dicom`, `read_dicom` |
| A transfer syntax is not one of the four | `parse_dicom`, `read_dicom` |
| Encapsulated pixel data, an RLE frame or a deflated data set is malformed | `parse_dicom`, `read_dicom`, `decode_rle_frame` |
| An image is not one grayscale sample, or `read_dicom` gets more than one frame | `parse_dicom`, `read_dicom`, `parse_dicom_frames` |
| The frames of a file differ in layout, bits or syntax | `encode_dicom_frames` |
| A grid is empty or holds more than 2^28 voxels | `ImageVolume`, `shepp_logan` |
| A file is not single-file NIfTI-1, or its datatype, unit or axes are not supported | `parse_nifti`, `read_nifti` |
| Slices disagree, share a position or are not evenly spaced | `stack_slices` |
| An index is outside the grid | `get`, `set`, `region_grow`, `render_slice` |
| A label is not from 0 to 255, or is the background where a region is needed | Label functions |
| A connectivity is not one of the three | `region_grow`, `keep_largest`, `label_pieces` |
| A window, step, ambient light or crop is out of range | `render_volume`, `render_slice` |
| A slab mode, thickness or plane count is out of range | `slab_projection` |
| A path has fewer than two points or two equal points in a row, `up` is zero or along a segment, or a size is out of range | `curved_reformat` |
| A circle has a bad axis, slice, center or radius, or holds no pixel center | `circle_statistics` |
| Two maps differ in grid or spacing, or a label is the background or empty | `compare_labels` |
| A shape or a slice area needs the background, an empty label, another grid or a bad axis | `label_shape`, `slice_areas` |
| A morphology label is the background, or its radius is negative or not finite | Morphology functions |
| A mesh has no triangle with area, or a smoothing factor is out of range | `weld_surface`, `smooth_surface`, `label_stl` |
| A mesh has no positions | `printable_stl` |
| A histogram has fewer than 2 bins or a bad range, or Otsu's method finds one full bin only | `Histogram`, `otsu_threshold` |
| A Gaussian width is not positive or reaches past 128 voxels, or a median radius is not from 1 to 3 | `gaussian_filter`, `median_filter` |

## Limits

- The reader takes little-endian grayscale images, uncompressed, deflated or RLE, of one frame or many. It does not read color, JPEG or JPEG 2000 files.
- The multi-frame reader reads the placement of each frame. It does not read the dimension index or the temporal position of a frame.
- The reader does not read a file that has no preamble.
- The NIfTI reader does not read NIfTI-2, a header and image pair, complex or color voxels, or sheared axes.
- A stack refuses a gantry tilt and slices that are not evenly spaced. It does not resample them.
- The ray caster runs on the CPU only. It has no GPU path and no parity test.
- Rendering uses the volume frame. It does not apply the patient orientation.
- A circle counts whole pixels by their centers. It does not weigh the pixels that its edge cuts.
- The connectivity of `label_surface`, the surfaces and the morphology is by faces. The `Connectivity` choice applies to the pieces and to region growing only.
- The colors of a transfer function are display values. They are not linear light.

## References

- NEMA PS3.5, "Data Structures and Encoding", sections 7.1 and 7.5, and annexes A and G.
- NEMA PS3.3, "Information Object Definitions", sections C.7.6.2 and C.11.2.1.
- NEMA PS3.10, "Media Storage and File Format", section 7.
- Cox and others, "A (sort of) new image data format standard: NIfTI-1", 2004, and the header `nifti1.h`.
- Otsu, "A threshold selection method from gray-level histograms", 1979.
- Hildebrand and Rüegsegger, "A new method for the model-independent assessment of thickness in three-dimensional images", 1997.
- Felzenszwalb and Huttenlocher, "Distance transforms of sampled functions", 2012.
- Shepp and Logan, "The Fourier reconstruction of a head section", 1974.
- Toft, "The Radon Transform: Theory and Implementation", 1996.
- Levoy, "Display of surfaces from volume data", 1988.
- Engel and others, "Real-Time Volume Graphics", 2006.
- Taubin, "A signal processing approach to fair surface design", SIGGRAPH 1995.
