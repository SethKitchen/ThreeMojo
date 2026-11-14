# Medical imaging

`extensions/imaging/` reads grayscale DICOM images and stacks them into volumes with physical spacing. It draws a volume with a ray caster, and it draws slices with labels and measurements. It is a library for research and teaching. It is not a medical device. Do not use it to diagnose, monitor or treat a patient.

![A cut head phantom, composited and as an isosurface, and one labeled axial slice with a measurement](out/medical-imaging.png)

`examples/medical_imaging.mojo` makes this picture. It cuts a head phantom into DICOM slices and writes each slice as a Part 10 file in memory. It then reads the files back and stacks them.

The left panel is the ray cast volume, cut in half. The middle panel is the same cut as an isosurface at 0.27. The right panel is the middle axial slice. The skull, the left ventricle and the largest feature are labeled, and a yellow line measures the head.

## Modules

| Module | What it gives |
|---|---|
| `ids` | `TransferSyntax`, `Photometric`, `PixelRepresentation`, `SliceAxis`, `RenderMode`, `SlabMode`, `Connectivity`, `LabelId` and `DicomNode` |
| `image_volume` | `ImageVolume`, a scalar grid with spacing, origin and axes, and `MILLIMETER64` |
| `dicom` | `parse_dicom`, `read_dicom`, `parse_dicom_frames` and `read_dicom_frames`, which give `DicomSlice` values, `decode_rle_frame`, `PetDose`, `Activity64`, `BECQUEREL`, `MEGABECQUEREL`, and `parse_dicom_tree` and `read_dicom_tree`, which give a `DicomTree` |
| `rtstruct` | `RtStructure`, `parse_rt_structures`, `read_rt_structures` and `structure_labels` |
| `suv` | `suv_factor`, `SuvFactor64`, `GRAM_PER_BECQUEREL`, `suv_volume`, `suv_statistics` and `SuvStatistics` |
| `dicom_write` | `DicomWriter`, `encode_dicom`, `encode_dicom_frames`, `encode_rle_frame`, `pack_bits` and `ds_text` |
| `series` | `stack_slices` and `volume_slices` |
| `nifti` | `parse_nifti`, `read_nifti`, `encode_nifti`, `encode_nifti_labels` and `labels_from_volume` |
| `phantom` | `shepp_logan`, a head of ten ellipsoids |
| `transfer` | `WindowLevel`, `TransferFunction` and `Rgba` |
| `raycast` | `VolumeCamera`, `orbit_camera`, `ray_box` and `render_volume` |
| `labels` | `LabelMap`, `threshold`, `region_grow`, `keep_largest`, `label_pieces`, `LabelPieces` and `label_surface` |
| `measure` | `label_statistics`, `voxel_distance`, `line_profile`, `LineProfile` and `full_width_half_maximum` |
| `shape` | `label_shape`, `LabelShape` and `slice_areas` |
| `compare` | `compare_labels`, `LabelComparison`, `label_overlaps`, `LabelOverlap`, `mean_dice`, `surface_voxels` and `percentile` |
| `roi` | `circle_statistics` and `RegionStatistics` |
| `texture` | `cooccurrence_matrix`, `volume_cooccurrence`, `texture_features` and `TextureFeatures` |
| `firstorder` | `intensity_features` and `IntensityFeatures` |
| `histogram` | `Histogram`, `volume_histogram`, `label_histogram`, `otsu_threshold`, `multi_otsu_thresholds` and `label_classes` |
| `filter` | `gaussian_filter`, `gaussian_kernel` and `median_filter` |
| `thickness` | `label_distance`, `local_thickness`, `thickness_statistics`, `ThicknessStatistics` and `seed_distances` |
| `gap` | `distance_from_label`, `label_gap`, `LabelGap` and `volume_within` |
| `morphology` | `dilate_label`, `erode_label`, `open_label` and `close_label` |
| `holes` | `fill_holes` and `fill_slice_holes` |
| `grow` | `confidence_connected` |
| `smooth` | `weld_surface`, `smooth_surface`, `surface_area` and `enclosed_volume` |
| `printing` | `printable_stl` and `label_stl` |
| `overlay` | `render_slice`, `overlay_labels`, `draw_measurement`, `draw_line`, `zoom_image`, `slice_size` and `label_color` |
| `contour` | `slice_outlines`, `slice_isolines`, `Outline` and `draw_outlines` |
| `fusion` | `overlay_values` and `hot_color` |
| `reformat` | `oblique_slice`, `slab_projection` and `sample_point` |
| `curved` | `curved_reformat` |
| `path` | `label_path`, `smooth_path` and `resample_path` |
| `resample` | `resample_volume`, `resample_labels`, `resample_onto` and `resample_labels_onto` |
| `crop` | `crop_volume`, `crop_labels`, `label_box` and `VoxelBox` |

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

For PET, the reader also keeps the elements in the next table, in the `PetDose` field `pet`. It reads the first item of the Radiopharmaceutical Information Sequence, of defined or undefined length. An empty element is absent, so a CT file with an empty weight reads as before.

| Tag | Element | Field of `pet` |
|---|---|---|
| (0008,0031) | Series Time | `series_time`, `has_series_time` |
| (0010,1030) | Patient's Weight | `patient_weight` |
| (0018,1072) | Radiopharmaceutical Start Time, in (0054,0016) | `injection_time`, `has_injection_time` |
| (0018,1074) | Radionuclide Total Dose, in (0054,0016) | `injected_dose` |
| (0018,1075) | Radionuclide Half Life, in (0054,0016) | `half_life` |
| (0054,1001) | Units | `units` |
| (0054,1102) | Decay Correction | `decay_correction` |

A time is `HH`, `HHMM`, `HHMMSS` or `HHMMSS.FFFFFF`, and the field holds the time after midnight.

Each value in `values` is `slope * stored + intercept`. For CT, this gives Hounsfield units. The reader masks each stored value to its stored bits. It extends the sign when the pixel representation is signed.

Lengths are in meters inside the library. DICOM gives them in millimeters. Use `MILLIMETER64` to read them back in millimeters. It has a `Float64` scale, so a length keeps every digit.

## Measure PET uptake

The standardized uptake value (SUV) of a PET image is the activity concentration over the injected activity per gram of body weight. A tracer spread evenly through the body gives an SUV of 1 g/mL everywhere. Oncology research reports the uptake of a tumor as SUV.

```mojo
var first = read_dicom("pet/slice001.dcm")
var factor = suv_factor(first.pet)
var suv = suv_volume(stack_slices(slices), factor)
var uptake = suv_statistics(suv, map, LabelId(1))
print(uptake.maximum.to(GRAM_PER_CUBIC_CENTIMETER), uptake.peak.to(GRAM_PER_CUBIC_CENTIMETER))
```

`suv_factor(dose)` gives the body weight in grams over the injected activity, in g/Bq. The values must be in `BQML`. With the decay correction `START`, the image is corrected to the start of the series. So the injected activity `A0` decays from the injection time to the series time:

    A = A0 2^(-(t_series - t_injection) / T_half)

A series time before the injection time means that midnight passed, so a day is added. With `ADMIN`, the image is corrected to the injection, and `A` is `A0`. The factor refuses `NONE`, other units, and an absent or zero weight, dose, half-life or time.

`suv_volume(volume, factor)` multiplies each value in Bq/mL by the factor, which gives SUV in g/mL. `suv_statistics(suv, map, label)` gives the largest SUV of a label and its mean. It also gives SUVpeak, the largest mean of a sphere of 1 mL centered on a voxel of the label. The sphere holds every voxel whose center is within its radius of 6.2 mm, in the label or not. PERCIST, the PET Response Criteria in Solid Tumors, uses SUVpeak. `peak_voxel` is the center of that sphere.

## Read an RT Structure Set

Radiotherapy plans and many research data sets give their regions as an RT Structure Set. A region, such as a tumor or an organ at risk, is a set of polygons on the slices of a CT. `read_rt_structures(path)` reads the regions, and `structure_labels` fills one region in a label map on the grid of a volume.

```mojo
var ct = stack_slices(slices)
var regions = read_rt_structures("plan/rtstruct.dcm")
for r in range(len(regions)):
    var map = structure_labels(regions[r], ct, LabelId(1))
    print(regions[r].name, map.voxels(LabelId(1)))
```

Each `RtStructure` has its ROI number, its name and its contours. Each point of a contour is in patient space, in meters. The reader keeps only the contours of the type `CLOSED_PLANAR`. It does not keep points, open contours or other types.

`structure_labels(structure, volume, label)` puts each contour on the slice nearest to the mean of its points. A pixel is in the region when its center is inside an odd number of the region's contours on its slice. Thus a contour inside another contour makes a hole, as most planning systems draw one. A contour of fewer than three points, or on a slice outside the volume, adds nothing.

`parse_dicom_tree(bytes)` and `read_dicom_tree(path)` read the elements of any Part 10 file into a `DicomTree`. Use them for a file that is not an image. The node `DATA_SET` is the data set, and each item of a sequence is a `DicomNode` of its own. `text`, `numbers`, `has` and `items` read a node by tag, such as `0x30060020`.

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

## Resample onto another grid

`resample_onto(volume, target, outside)` brings a volume onto the grid of another volume, in patient space. Use it to bring a PET volume onto the grid of a CT, so that the two can be drawn and measured together.

```mojo
var pet_on_ct = resample_onto(pet, ct, 0)
var labels_on_ct = resample_labels_onto(pet_labels, pet, ct)
```

The result takes the size, spacing, origin and axes of `target`, and the window of `volume`. Each voxel takes the trilinear value of `volume` at its patient position. A voxel whose center falls outside the box of the voxel centers of `volume` gets `outside`. The two volumes need not share their spacing, their extent or the turn of their axes.

`resample_labels_onto(map, placed, target)` does the same for a label map, which `placed` puts in patient space. Each voxel takes the label of the nearest voxel center of `map`, rounded half up along each axis. A voxel whose nearest center is outside `map` is background.

## Crop to a region

An analysis often needs only the region around one structure. Crop the volume and its label map to that region, and every later step runs on fewer voxels.

```mojo
var box = label_box(map, LabelId(1), 4)
var part = crop_volume(volume, box)
var labels = crop_labels(map, box)
```

A `VoxelBox` holds the first and the last voxel of a region along each axis. Both are kept. `label_box(map, label, margin)` gives the box of one label, grown by `margin` voxels on each side and cut at the grid's edge. `crop_volume` and `crop_labels` copy the voxels of a box. A box that leaves the grid or holds no voxel is refused.

The cropped volume keeps its place in patient space. Its origin is the center of the box's first voxel, with the same axes and spacing. So a point has the same patient position before and after the crop. The crop keeps the window and the photometric interpretation of the volume.

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

## Grow a region by its statistics

`confidence_connected(volume, seeds, multiplier, iterations, radius, label)` grows a region from seeds without a range of values to give. It finds the range itself, as ITK's `ConfidenceConnectedImageFilter` does. Use it to segment a lesion or an organ with a smooth inside from one click.

```mojo
var lesion = confidence_connected(volume, [(80, 64, 40)], 2.5, 4, 1, LabelId(1))
```

A box of `radius` voxels each way around each seed gives a mean and a sample variance. A box that leaves the grid repeats the edge voxels. The mean of the means and the mean of the variances give the first range, `mean` plus or minus `multiplier` standard deviations. The region grows by faces from each seed whose value is in the range, through voxels whose values are in it, ends included.

Each of the `iterations` takes the mean and the sample variance of the region, and grows the region again from the seeds. A region of one voxel, or of zero variance, stops the iterations. A seed outside its own range grows nothing. A value that is not a number never joins a region, and it spoils the range of a seed whose box holds it.

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

## Fill the holes of a label

`fill_holes` gives a label to each part of the background that the label closes off. Such a hole has no path to the grid's edge through voxels outside the label. A threshold of a bone or an organ often leaves holes, such as the marrow of a bone or a vessel in the liver.

```mojo
var solid = fill_holes(map, LabelId(1))
var axial = fill_slice_holes(map, LabelId(1), K_AXIS)
```

`fill_slice_holes` fills the holes of each slice across one axis. Use it for a tube that is open at its two ends, such as an airway. The tube has no hole in three dimensions, but each slice across it has one.

The connectivity is that of the voxels outside the label as they look for the edge. With `FACES`, the default, they move through faces only. So a wall of the label closes a hole where its voxels touch at an edge or a corner. With `CORNERS`, they also pass between two voxels of the label that share only a corner. In a slice, `FACES` gives four neighbors, and `EDGES` and `CORNERS` give eight.

A voxel of another label in a hole keeps its label, and a path to the edge can pass through it. Unlike `close_label`, a fill has no radius. It fills a hole of any size, but not a gap that is open to the edge.

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

`multi_otsu_thresholds(histogram, classes)` splits the voxels into 2 to 8 classes, such as the fluid, the gray matter and the white matter of a brain. It gives the `classes - 1` edges with the largest variance between the classes. A search by dynamic programming finds the best split exactly, and each class holds a voxel. With two classes, it gives the edge of `otsu_threshold`.

```mojo
var edges = multi_otsu_thresholds(counts, 3)
var tissues = label_classes(volume, edges)
```

`label_classes(volume, thresholds)` gives each voxel the label `1 + k`, where `k` is the number of edges at or below its value. So the darkest class is label 1, and a value that is not a number is background. Of two splits with the same variance, the search keeps the lower edges, class by class from the top. The histogram can have up to 4096 bins.

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

## Measure first-order features

`intensity_features` gives the first-order features of the values inside one label. They describe the spread of the values, without regard to where the values are. Radiomics uses them together with the texture features.

```mojo
var f = intensity_features(volume, map, LabelId(1), 32, -100, 300)
print(f.mean, f.deviation, f.skewness, f.median, f.entropy)
```

| Feature | Definition |
|---|---|
| `mean`, `deviation` | The mean and the standard deviation, with `n` and not `n - 1` |
| `skewness`, `kurtosis` | The third and the fourth central moments, over the third and the fourth powers of the deviation. A normal law has a kurtosis of 3 |
| `minimum`, `p10`, `median`, `p90`, `maximum` | The 0th, 10th, 50th, 90th and 100th percentiles |
| `interquartile` | The 75th percentile less the 25th |
| `energy` | The sum of the squared values |
| `entropy` | `-sum(p log2 p)` over the shares `p` of a histogram, in bits |
| `uniformity` | The sum of `p^2` over the same histogram |

The percentiles interpolate linearly between ranks, as numpy does by default. The histogram has `bins` bins of equal width from `low` to `high`. A value below `low` goes into the first bin, and a value above `high` goes into the last bin. A region of one value has a skewness and a kurtosis of 0. The definitions are those of numpy's `std` and `percentile`, and of scipy's `skew` and `kurtosis` with `fisher=False`.

## Measure texture

Radiomics describes the texture of a region, such as a lesion, by how often two gray levels sit side by side. `cooccurrence_matrix` counts the gray levels of each pair of pixels at an offset, in one slice and inside one label. `texture_features` gives the Haralick features of the matrix.

```mojo
var m = cooccurrence_matrix(volume, map, LabelId(1), K_AXIS, 40, 1, 0, 32, -100, 300)
var f = texture_features(m[0], m[1])
print(f.contrast, f.homogeneity, f.energy, f.correlation)
```

The values first go into `levels` gray levels: level `floor((value - low) / (high - low) * levels)`, kept from 0 to `levels - 1`. The offset `(dx, dy)` is in pixels of the slice, as `render_slice` draws it. `(1, 0)` pairs each pixel with its neighbor along pixel x, and `(1, 1)` with its diagonal neighbor. Both pixels of a pair must be in the label. The matrix is symmetric, and its entries `P(i, j)` sum to 1.

| Feature | Formula |
|---|---|
| `contrast` | The sum of `P (i - j)^2` |
| `dissimilarity` | The sum of `P abs(i - j)` |
| `homogeneity` | The sum of `P / (1 + (i - j)^2)` |
| `asm` | The angular second moment, the sum of `P^2` |
| `energy` | The square root of `asm` |
| `correlation` | The sum of `P (i - mu_i) (j - mu_j) / (sigma_i sigma_j)`, or 1 when a sigma is below 1e-15 |

`volume_cooccurrence(volume, map, label, di, dj, dk, levels, low, high)` counts the pairs of a whole label in three dimensions instead, at a voxel offset. Use it for a texture across slices, such as along the axis of a bone. With `dk` zero, it is the matrices of every slice pooled.

These are the formulas of scikit-image's `graycoprops`. Its angle `theta` at the distance `d` is the offset `(round(d cos theta), round(d sin theta))`.

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

`label_overlaps(first, second)` compares two maps of many labels at once, such as two segmentations of several organs. It lists every label other than the background that either map holds, in label order. Each `LabelOverlap` holds the voxel counts of the label in each map, the shared voxels, the Dice coefficient and the Jaccard index. `mean_dice(table)` gives the mean Dice over the labels, each with one weight.

```mojo
var table = label_overlaps(reference, automatic)
for entry in table:
    print(entry.label.value, entry.dice)
print("mean Dice", mean_dice(table))
```

A label that only one map holds has a Dice of 0. The table counts voxels only. Use `compare_labels` for the surface distances of a label.

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

## Measure the gap between two labels

`label_gap(map, first, second)` gives the least distance between a voxel of one label and a voxel of another. Use it for the distance from a tumor to a vessel, or from a lesion to an organ. It also gives the two voxels, as `(i, j, k)`.

```mojo
var gap = label_gap(map, LabelId(1), LabelId(2))
print(gap.distance.to(MILLIMETER64), gap.first_voxel[2], gap.second_voxel[2])
var near = volume_within(map, LabelId(1), LabelId(2), Length64(5, MILLIMETER64))
var field = distance_from_label(map, LabelId(1))
```

| Function | What it gives |
|---|---|
| `label_gap(map, first, second)` | The least distance, and the voxel of each label where it is |
| `volume_within(map, first, second, limit)` | The volume of the voxels of `second` within `limit` of `first` |
| `distance_from_label(map, label)` | A volume in millimeters: the distance of each voxel to the nearest voxel of the label |

Every distance is center to center, with the spacing of each axis, and exact. So two labels that share a face are one spacing apart. The clear space between the faces of their voxels is less, by about one voxel. Of two pairs at one distance, the voxel of `second` with the lowest index counts. Then the nearest voxel of `first` with the lowest index counts.

Draw `distance_from_label` with `render_slice`, or give it to `label_statistics` with the map of another label. The second label then gets the mean, the least and the largest distance of its voxels.

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

The lateral direction changes at each corner of the path. A path of many short segments gives a smooth image.

`label_path(map, volume, label, start, end)` finds such a path through a label, between two of its voxels. It keeps to the middle of the label, as a centerline does.

```mojo
var centerline = label_path(map, volume, LabelId(1), (40, 52, 10), (61, 70, 88))
var image = curved_reformat(volume, centerline, v3(0, 0, 1), 40, Length64(0.5, MILLIMETER64), -1000)
```

Each step of the path goes to one of the 26 neighbors of a voxel, inside the label. A step of length `s` between voxels at the distances `d1` and `d2` from the label's edge costs `s * (1 / d1^2 + 1 / d2^2) / 2`. A step near the edge costs much more than a step down the middle.

Dijkstra's method finds the path of least total cost. The distances are exact, with the spacing of each axis, and the grid's edge counts as outside.

A chain of voxel centers turns in steps of 45 degrees, so a curved reformat along it has jagged edges. Smooth it first, and give it even steps:

```mojo
var even = resample_path(smooth_path(centerline, 4), Length64(0.25, MILLIMETER64))
```

`smooth_path(path, passes)` puts each inner point at `(before + 2 * point + after) / 4` in each pass, and keeps the two ends. A straight run stays where it is, and a zigzag of one step goes flat in one pass. `resample_path(path, spacing)` places points at the arc lengths 0, `spacing`, `2 * spacing` and on, and ends at the path's last point. The result keeps the window of the source. It is not a plane in patient space, so its origin is zero and its axes are those of the grid.

![A winding vessel: its projection with the centered path in yellow, one axial slice with the label outlined, and the vessel straightened with a narrowing](out/vessel.png)

`examples/vessel.mojo` makes this picture. A synthetic vessel of 300 HU winds through soft tissue of about 40 HU, in all three axes. Its radius is 2.4 mm, and it narrows to half of that partway along. A threshold labels it, and `keep_largest` keeps it whole with `CORNERS`. `label_path` finds its centered path. `smooth_path` and `resample_path` smooth it, and `curved_reformat` straightens the vessel along it.

The top left panel is the maximum intensity projection along z, with the path in yellow. The top right panel is one axial slice, which cuts the vessel once. `slice_outlines` and `draw_outlines` outline the label in yellow. The band below is the straightened vessel, where the narrowing is plain to see. Along the path of 54.7 mm, the distance to the edge is least at 34.9 mm: 1.12 mm, against the narrowest radius of 1.2 mm. The distance runs to the centers of the voxels outside, so it is less than the radius.

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

`zoom_image(image, factor)` scales an image up by repeating each pixel. `draw_line(image, x0, y0, x1, y1, color)` draws a line of pixels, and skips the pixels past the edge.

## Outline a label

`slice_outlines(map, label, axis, index)` gives the outlines of a label in one slice, by marching squares. Each `Outline` holds its points in voxel units, `(i, j, k)`, its length and the area that it closes. `draw_outlines` draws them on a slice image, also a zoomed one.

```mojo
var outlines = slice_outlines(map, LabelId(1), K_AXIS, 40)
var image = zoom_image(render_slice(volume, K_AXIS, 40), 3)
draw_outlines(image, K_AXIS, outlines, 3, Rgba(1, 0.86, 0.16, 1))
print(outlines[0].length.to(MILLIMETER64))
```

The outline crosses each side between a pixel of the label and a pixel outside it, at the middle of the side. A pixel past the edge of the slice is outside, so every outline closes. Two pixels of the label that touch only at a corner have outlines of their own. This is the rule of scikit-image's `find_contours` at the level 0.5.

The area of an outer outline is positive, and the area of a hole is negative. So the sum over the outlines of a slice is the area inside the label's outlines. It is a little less than the area of the pixels, because the outline cuts each corner. Use `slice_areas` for the area of the pixels.

## Draw isolines

`slice_isolines(volume, axis, index, level)` gives the lines where the values of a slice cross a level. Use it for the line of an SUV level on a PET, or for an isotherm of a heat field. The lines are `Outline` values, so `draw_outlines` draws them, and each has its length and area.

```mojo
var half = slice_isolines(suv, K_AXIS, 40, 0.5 * peak)
draw_outlines(image, K_AXIS, half, 3, Rgba(0.3, 1, 0.4, 1))
```

A line crosses each side of a square between a pixel at or past the level and a pixel below it. It crosses where the linear blend of the two values is the level, as scikit-image's `find_contours` does. A pixel past the edge of the slice is below every level, so a line closes through the centers of the edge pixels. The area of a line around values past the level is positive, and around a dip below it negative. The level and the values of the slice must be finite.

## Fuse PET over CT

`overlay_values(image, volume, axis, index, low, high, opacity, zoom)` blends the values of a second volume over a slice image. Use it to show a PET over the anatomy of a CT. The second volume must be on the grid of the slice, so bring it there with `resample_onto` first.

```mojo
var suv_on_ct = resample_onto(suv_volume(pet, suv_factor(first.pet)), ct, 0)
var image = zoom_image(render_slice(ct, K_AXIS, 40), 3)
overlay_values(image, suv_on_ct, K_AXIS, 40, 1.0, 8.0, 0.75, 3)
```

The color runs on the hot scale from `low` to `high`. It is dark at the bottom, red at a third, yellow at two thirds and white at the top. `hot_color(t)` gives it. A value below `low` leaves its pixel as it is. The color covers a pixel with the weight `opacity * min(1, 3 t)`, where `t` is the share of the range. So a value just past `low` fades in, and the edge of the threshold does not show as a dark rim.

![A head phantom CT, a synthetic PET in SUV, and the two fused with a lesion outlined](out/fusion.png)

`examples/fusion.mojo` makes this picture. The CT is the head phantom on voxels of 1.56 mm. The PET is synthetic, on 4 mm voxels placed apart from the CT's. The brain takes up a little tracer, and a lesion of 8 mm radius takes up five times more. A Gaussian of 3 mm blurs the PET, as the resolution of a scanner does. The example turns the PET into SUV, brings it onto the CT's grid, and labels the lesion at 40 percent of the largest SUV.

The lesion has 976 voxels, an SUVmax of 7.6, an SUVmean of 4.6 and an SUVpeak of 6.2. The overlay runs from SUV 2 to 8, so the brain's own uptake, near SUV 1.7, does not show.

## Verification

The tests check these results:

- A slice written by `encode_dicom` reads back with every element equal, in each of the four transfer syntaxes.
- Two enhanced CT files of three frames that pydicom 3.0.1 wrote, native and RLE, read with pydicom's values. Each frame takes its position and window from its own groups, and its rescale, spacing and orientation from the shared groups.
- A volume written as a multi-frame file in each of the four transfer syntaxes reads back the same. pydicom reads the native and the RLE files. That check is not part of the test suite.
- Three files that pydicom 3.0.1 wrote read with pydicom's values. They are 16-bit signed RLE, 8-bit RLE and deflated. `assets/dicom/make_dicom.py` makes them.
- `pack_bits` splits runs and literals at 128 bytes, and its code decodes to the same bytes.
- Two PET files that pydicom 3.0.1 wrote read with pydicom's elements. One is explicit VR with a sequence of undefined length, and one is implicit VR with a sequence of defined length. Their SUV factor matches the factor from pydicom's values to 1e-14. `assets/dicom/make_pet.py` makes them.
- A time reads in each of its four forms, and a leap second is 86400 s. Empty elements are absent. Of two items or two dose sequences, the first counts. Thirteen malformed times and three times past a day are refused.
- An injection at 23:50 and a series at 00:20 decay the dose for 1800 s. With `ADMIN`, the dose does not decay. On a grid of 4 by 4 by 3 mm voxels, SUVpeak matches a search of every voxel near each center of the label. This holds at the grid's edge too. On a flat SUV, the lowest voxel counts.
- Two RT Structure Sets that pydicom 3.0.1 wrote read with pydicom's regions and points. One is explicit VR with sequences and items of undefined length. The other is implicit VR with defined lengths. `assets/dicom/make_rtstruct.py` makes them.
- The fixture grid has 24 by 20 by 4 voxels of 2 by 2.5 by 3 mm. On it, each region fills the voxels that scikit-image 0.26's `points_in_poly` puts inside. The contours of a slice join by exclusive or. The test compares each voxel. The tumor has 68 voxels, the ring with a square hole has 87, and the marker point has none.
- A square from 0 to 10 mm fills the 20 pixel centers inside it. Contours past the grid, beside it and of two points fill nothing.
- A tree reads nested sequences, sequences of defined length in implicit VR, and empty elements. It steps over encapsulated pixel data. Of two elements or two sequences with one tag, the first counts. A bad preamble, a bad syntax, a stray or unknown delimiter, an item without an end and nesting past 64 levels are refused.
- A 12-bit signed value masks and extends its sign: `0xF800` reads as -2048.
- A volume cut into slices, written, read and stacked gives the same values and spacing.
- `trilinear` is exact for a linear field.
- An oblique reformat of a linear field matches the field at every pixel.
- Smoothing keeps a straight run on its line and its ends in place, and flattens a zigzag of one step in one pass. A bent path resampled every 0.5 mm has its corner on a sample, and every step is 0.5 mm.
- The centered path through a straight tube runs down its axis, and a start off the axis joins the axis. Through a bent tube, each step goes to a neighbor inside the label, and the path straightens into a curved reformat.
- A curved reformat along a straight path matches a linear field at every pixel. Along a bent path, the corner falls at its arc length, and an `up` that leans along the path keeps only its square part. A point past the volume takes the `outside` value.
- A crop keeps each value, and each voxel keeps its patient position on turned axes. A label box grows by its margin, and the grid's edge cuts it.
- A linear field on a turned grid, resampled onto a finer grid of other axes, keeps its value at every voxel inside. Every voxel outside gets the `outside` value. A volume and a label map resampled onto their own grid are the same. A label map onto a finer grid matches a search for each nearest voxel.
- A random volume and label map on a turned grid were resampled onto a finer grid that reaches past them. Inside the box of the voxel centers, the values match scipy's `map_coordinates` of order 1 to Float32 rounding. Two voxels on the face of the box, 1e-16 outside it, count as inside here and outside in scipy. Inside the box, the labels match scipy's order 0. In the half voxel past the box, the labels keep the nearest voxel, which still covers the point, where scipy gives the background. That check is not part of the test suite.
- A linear field resampled from 0.5 x 0.5 x 3 mm voxels to 1 mm cubes keeps its value at every new voxel. A label slice of 3 mm becomes the three 1 mm slices nearest to it.
- A slab of four planes through a ramp gives its top plane as its maximum and its bottom plane as its minimum. Its mean is its center value.
- A uniform volume of opacity 0.25 per voxel, four voxels deep, passes `0.75^4` of the background.
- An isosurface of a linear ramp has the full iso color along the gradient, and the ambient light across it.
- An ellipsoid of 904.8 voxels labels 879 voxels, within four percent, with its centroid exact.
- A Gaussian keeps a linear ramp away from the edges. Its response to one voxel is the product of its three kernels, and sums to one.
- A median removes a hot and a cold voxel and keeps the edge between two regions.
- On two overlapping distributions, the Otsu edge is the edge with the least variance within the classes, found by brute force over the voxels.
- With two classes, the multi-level split gives the Otsu edge on five random histograms. Three peaks split at the lowest edges between them. Each filled bin is a class when there are as many classes as filled bins. A value at an edge joins the class above it.
- On 12 histograms of four bumps, the splits into 3, 4 and 5 classes match scikit-image 0.26's `threshold_multiotsu` bin for bin. That check is not part of the test suite.
- A textured box of 100 in a background of 0 grows to its edge. It does so from one seed, from two seeds, and from one seed given twice. A seed at the grid's corner grows the background. A spike or a dip outside its own range grows nothing. A box of radius 0 grows only the seed's own value, and a flat volume fills.
- From five seeds with other multipliers, iterations and radii, the regions on a smooth random volume match SimpleITK 2.5.7's `ConfidenceConnected` voxel for voxel. They hold from 9,000 to 26,000 voxels. That check is not part of the test suite.
- Two voxels that share an edge are one piece with `EDGES` and `CORNERS`, and two with `FACES`. Two that share a corner only are one piece with `CORNERS`. A diagonal line grows from its end with `CORNERS`, and not with `FACES`. On a random grid of 30 by 28 by 26 voxels, the pieces of each connectivity match scipy's `ndimage.label` in count and size. That check is not part of the test suite.
- Cubes of 27 and 8 voxels and two single voxels number 1 to 4. A voxel that touches a cube at a corner only is a piece of its own.
- A Gaussian blob of sigma 2 mm has a full width at half maximum of `2 sqrt(2 ln 2) sigma`, within 1 percent. A box 5 voxels wide is exactly 5 mm wide.
- One pixel has a diamond outline of half its area. A rectangle of 3 by 2 pixels of 0.5 by 0.8 mm has its exact cut length and area. A ring gives its outer outline and a hole with a negative area. Pixels that touch at a corner have two outlines, and pixels that share a side have one.
- A ramp crossed at 2.5 gives a line at x = 2.5 that closes along the edge, with its exact length and area. A level at a pixel's value puts the line on the pixel. A dip gives a hole of negative area. The half maximum of a Gaussian of sigma 3 pixels is a circle of radius `sigma sqrt(2 ln 2)`, in length and area to 2 percent.
- A smooth random slice has 8, 6 and 12 isolines at three levels. Each matches scikit-image 0.26's `find_contours` in point count, and in length and area to 2e-5 mm. That is the precision of the values passed to it as text. That check is not part of the test suite.
- On 9 slices of a random map across the three axes, all 429 outlines match scikit-image 0.26's `find_contours`. Their point counts are the same, their lengths match to 2e-12 mm and their areas to 1e-13 mm^2. That check is not part of the test suite.
- The hot scale is dark at 0, red at a third, yellow at two thirds and white at 1. On a slice of six values, each pixel blends to the byte of its color and weight. A value below the range keeps its pixel. A value at a sixth of the range fades in at half the weight. Each axis and a zoom of 2 map the pixels to their voxels.
- A circle of 2 pixels holds the 13 lattice points of its disc. On a ramp, a disc gives the value at its center and the sample deviation of its pixels. With pixels 0.5 mm wide, a circle of 1 mm holds 7 pixels. A circle at a corner keeps the 6 pixels of the grid.
- The values 1, 2, 3, 4 and 10 have a mean of 4 and a deviation of `sqrt(10)`. Their 10th percentile is 1.4, and their 90th percentile is 7.6. Their histogram entropy matches numpy to the last digit. The entropy uses `log`, because the Float64 `log2` of Mojo 1.2 is off by about 1e-9.
- On the 761 voxels of an ellipsoid, every first-order feature matches numpy 2.1.3 and scipy 1.18.1 to 1e-14, relative. That check is not part of the test suite.
- A board in three dimensions flips along k, with a contrast of 1, and not along `(1, 1, 0)`. With `dk` zero, its matrix is the matrices of the slices pooled, to 1e-15.
- On a checkerboard, neighbors along x give a contrast of 1 and a correlation of -1. Diagonal neighbors give a contrast of 0 and a correlation of 1. The gray levels clamp at both ends, and only pairs in the label count. On a random image of 8 levels, the six features at 8 offsets match scikit-image 0.26 to 4e-15. That check is not part of the test suite.
- A box of 10 by 6 by 8 mm has voxels of 1 by 1 by 2 mm. Its semi-axes are `sqrt(5 / 12)` times its sides, to 1e-9, along the grid axes. Its axes follow the patient frame of the volume. An ellipsoid of 20, 12 and 8 mm turned 30 degrees gives its semi-axes within 2 percent, and its long axis within one degree. Each slice of the box has its area exactly.
- A table of four labels gives each label's counts, Dice and Jaccard. The Dice is 1 for a match, 0.5 for half, and 0 for a label in one map only. Its overlap of a label agrees with `compare_labels`.
- A label against itself has a Dice coefficient of 1 and no surface distance. Two boxes that overlap by half have a Dice of 0.5 and a Jaccard of 1/3. Their Hausdorff distance is their shift, and their HD95 and ASSD match a search of every pair. Two ellipsoids in voxels of 0.7, 0.9 and 1.5 mm match MedPy 0.5 to 1e-7 mm in every measure. That check is not part of the test suite.
- A hollow cube fills its 27 voxels, and a voxel of another label in it keeps its label. A center walled by its 6 face neighbors fills with `FACES` only. A wall of its 18 neighbors fills it with `FACES` and `EDGES`, and not with `CORNERS`.
- A label on the grid's edge closes off the inside, and one gap opens it. A tube open at its ends has no hole in three dimensions, and the slices across its axis fill its center.
- On a random grid of 30 by 28 by 26 voxels, each fill matches scipy's `binary_fill_holes`. The check covers each connectivity, in three dimensions and in the slices of each axis. That check is not part of the test suite.
- Two boxes four voxels of 0.5 mm apart have a gap of 2 mm, at the voxels that face each other. A slanted pair in voxels of 0.5, 0.8 and 2 mm has its exact gap. A pair that shares a face is one spacing apart. The distance map matches a search of every seed at every voxel. With `label_statistics`, it gives the least, the mean and the largest distance of a label.
- A lumpy ball and a winding tube lie in voxels of 0.7, 0.9 and 2.5 mm. Their gap and its two voxels match a search of every pair of voxels. The distance map matches scipy's `distance_transform_edt` to 1e-7, relative. That check is not part of the test suite.
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
| A PET time is not `HHMMSS.FFFFFF` or not a time of day, or a weight, dose or half-life is not a number | `parse_dicom`, `read_dicom` |
| An SUV has values not in `BQML`, a decay correction not `START` or `ADMIN`, or no weight, dose, half-life or time | `suv_factor` |
| An SUV factor is not positive and finite, or a label is bad, the background, empty or on another grid | `suv_volume`, `suv_statistics` |
| A file is not an RT Structure Set, a region has not one ROI number, a contour refers to no region, or a closed contour has fewer than three points | `parse_rt_structures`, `read_rt_structures` |
| A sequence holds an element that is not an item, an item has no end, the sequences nest more than 64 deep, or a node is not in the tree | `parse_dicom_tree`, `read_dicom_tree`, `DicomTree` |
| A structure label is not valid or is the background | `structure_labels` |
| A file is not single-file NIfTI-1, or its datatype, unit or axes are not supported | `parse_nifti`, `read_nifti` |
| Slices disagree, share a position or are not evenly spaced | `stack_slices` |
| An index is outside the grid | `get`, `set`, `region_grow`, `render_slice` |
| A label is not from 0 to 255, or is the background where a region is needed | Label functions |
| A connectivity is not one of the three | `region_grow`, `keep_largest`, `label_pieces` |
| A grown region has no seed, a seed outside the grid, a bad label, or a multiplier, an iteration count or a radius out of range | `confidence_connected` |
| A window, step, ambient light or crop is out of range | `render_volume`, `render_slice` |
| An outline or isoline has a bad label, the background, a bad axis or slice, a level or a value that is not finite, or a zoom out of range | `slice_outlines`, `slice_isolines`, `draw_outlines`, `zoom_image` |
| An overlay has a bad axis or slice, a range that is not finite or does not rise, an opacity or a zoom out of range, or an image of another size | `overlay_values` |
| A slab mode, thickness or plane count is out of range | `slab_projection` |
| An end of a centered path is outside the grid or the label, or no path joins the ends | `label_path` |
| A path has fewer than two points or two equal points in a row, or a pass count or a spacing is out of range | `smooth_path`, `resample_path` |
| A path has fewer than two points or two equal points in a row, `up` is zero or along a segment, or a size is out of range | `curved_reformat` |
| A circle has a bad axis, slice, center or radius, or holds no pixel center | `circle_statistics` |
| A texture has a bad label, axis, slice, offset, level count or range, or no pair at its offset | `cooccurrence_matrix`, `volume_cooccurrence`, `texture_features` |
| A first-order feature has another grid, a bad or empty label, a bad bin count or a bad range | `intensity_features` |
| Two maps differ in grid or spacing, or a label is the background or empty | `compare_labels`, `label_overlaps` |
| A label map and the volume that places it differ in grid or spacing | `resample_labels_onto` |
| A table of overlaps is empty | `mean_dice` |
| A crop box leaves the grid or holds no voxel, or a label box has a bad label or margin | `crop_volume`, `crop_labels`, `label_box` |
| A shape or a slice area needs the background, an empty label, another grid or a bad axis | `label_shape`, `slice_areas` |
| A morphology label is the background, or its radius is negative or not finite | Morphology functions |
| A hole fill has a bad label, the background, a bad connectivity or a bad axis | `fill_holes`, `fill_slice_holes` |
| A gap has a bad, background or empty label, the same label twice, or a negative or infinite limit | `label_gap`, `volume_within`, `distance_from_label` |
| A mesh has no triangle with area, or a smoothing factor is out of range | `weld_surface`, `smooth_surface`, `label_stl` |
| A mesh has no positions | `printable_stl` |
| A histogram has fewer than 2 bins or a bad range, or Otsu's method finds one full bin only | `Histogram`, `otsu_threshold` |
| A split has classes out of 2 to 8, more than 4096 bins or too few full bins, or thresholds that are not finite and rising | `multi_otsu_thresholds`, `label_classes` |
| A Gaussian width is not positive or reaches past 128 voxels, or a median radius is not from 1 to 3 | `gaussian_filter`, `median_filter` |

## Limits

- The reader takes little-endian grayscale images, uncompressed, deflated or RLE, of one frame or many. It does not read color, JPEG or JPEG 2000 files.
- The multi-frame reader reads the placement of each frame. It does not read the dimension index or the temporal position of a frame.
- The reader does not read a file that has no preamble.
- The writer does not write the PET elements. An SUV is by body weight only, not by lean body mass. The factor takes the series time as the start of the scan, and does not read the private scale factors of a vendor.
- A structure set gives its closed planar contours only. A pixel is in a region by its center and the even-odd rule. A pixel that a contour cuts counts whole or not at all. A contour goes to its nearest slice. The reader does not check the CT series or the frame of reference that the structure set refers to.
- The NIfTI reader does not read NIfTI-2, a header and image pair, complex or color voxels, or sheared axes.
- A stack refuses a gantry tilt and slices that are not evenly spaced. It does not resample them.
- The ray caster runs on the CPU only. It has no GPU path and no parity test.
- Rendering uses the volume frame. It does not apply the patient orientation.
- A circle counts whole pixels by their centers. It does not weigh the pixels that its edge cuts.
- A co-occurrence offset is in voxels. With voxels that are not cubes, two offsets of one count of voxels can differ in length.
- A centered path is a chain of voxel centers. `smooth_path` smooths it, but does not keep it inside the label at a sharp bend of a thin structure.
- The connectivity of `label_surface`, the surfaces and the morphology is by faces. The `Connectivity` choice applies to the pieces and to region growing only.
- The colors of a transfer function are display values. They are not linear light.

## References

- Haralick, Shanmugam and Dinstein, "Textural features for image classification", 1973.
- Wahl and others, "From RECIST to PERCIST: Evolving considerations for PET response criteria in solid tumors", Journal of Nuclear Medicine, 2009.
- Boellaard and others, "FDG PET/CT: EANM procedure guidelines for tumour imaging: version 2.0", 2015.
- NEMA PS3.3, "Information Object Definitions", sections C.8.9.1 and C.8.9.2, the PET Series and PET Isotope modules.
- NEMA PS3.3, "Information Object Definitions", sections C.8.8.5 and C.8.8.6, the Structure Set and ROI Contour modules.
- Zwanenburg and others, "The Image Biomarker Standardization Initiative", Radiology, 2020.
- NEMA PS3.5, "Data Structures and Encoding", sections 7.1 and 7.5, and annexes A and G.
- NEMA PS3.3, "Information Object Definitions", sections C.7.6.2 and C.11.2.1.
- NEMA PS3.10, "Media Storage and File Format", section 7.
- Cox and others, "A (sort of) new image data format standard: NIfTI-1", 2004, and the header `nifti1.h`.
- Otsu, "A threshold selection method from gray-level histograms", 1979.
- Johnson and others, "The ITK Software Guide, Book 2: Design and Functionality", 4th edition, 2015.
- Hildebrand and Rüegsegger, "A new method for the model-independent assessment of thickness in three-dimensional images", 1997.
- Felzenszwalb and Huttenlocher, "Distance transforms of sampled functions", 2012.
- Shepp and Logan, "The Fourier reconstruction of a head section", 1974.
- Toft, "The Radon Transform: Theory and Implementation", 1996.
- Levoy, "Display of surfaces from volume data", 1988.
- Engel and others, "Real-Time Volume Graphics", 2006.
- Taubin, "A signal processing approach to fair surface design", SIGGRAPH 1995.
