# Medical imaging

`extensions/imaging/` reads grayscale DICOM images and stacks them into volumes with physical spacing. It draws a volume with a ray caster, and it draws slices with labels and measurements. It is a library for research and teaching. It is not a medical device. Do not use it to diagnose, monitor or treat a patient.

![A cut head phantom, composited and as an isosurface, and one labeled axial slice with a measurement](out/medical-imaging.png)

`examples/medical_imaging.mojo` makes this picture. It cuts a head phantom into DICOM slices and writes each slice as a Part 10 file in memory. It then reads the files back and stacks them.

The left panel is the ray cast volume, cut in half. The middle panel is the same cut as an isosurface at 0.27. The right panel is the middle axial slice. The skull, the left ventricle and the largest feature are labeled, and a yellow line measures the head.

## Modules

| Module | What it gives |
|---|---|
| `ids` | `TransferSyntax`, `Photometric`, `PixelRepresentation`, `SliceAxis`, `RenderMode` and `LabelId` |
| `image_volume` | `ImageVolume`, a scalar grid with spacing, origin and axes, and `MILLIMETER64` |
| `dicom` | `parse_dicom` and `read_dicom`, which give a `DicomSlice` |
| `dicom_write` | `DicomWriter`, `encode_dicom` and `ds_text` |
| `series` | `stack_slices` and `volume_slices` |
| `nifti` | `parse_nifti`, `read_nifti`, `encode_nifti`, `encode_nifti_labels` and `labels_from_volume` |
| `phantom` | `shepp_logan`, a head of ten ellipsoids |
| `transfer` | `WindowLevel`, `TransferFunction` and `Rgba` |
| `raycast` | `VolumeCamera`, `orbit_camera`, `ray_box` and `render_volume` |
| `labels` | `LabelMap`, `threshold`, `region_grow`, `keep_largest` and `label_surface` |
| `measure` | `label_statistics` and `voxel_distance` |
| `overlay` | `render_slice`, `overlay_labels`, `draw_measurement` and `label_color` |
| `reformat` | `oblique_slice` |

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

## What the reader takes

A Part 10 file starts with a preamble of 128 bytes and the letters `DICM`. The file meta group follows in explicit VR little endian. Its transfer syntax UID gives the encoding of the data set.

The reader takes these two transfer syntaxes:

| Transfer syntax | UID |
|---|---|
| Explicit VR little endian | `1.2.840.10008.1.2.1` |
| Implicit VR little endian | `1.2.840.10008.1.2` |

The reader refuses big endian and every compressed syntax. It refuses encapsulated pixel data too. Convert such a file to an uncompressed syntax first.

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
| (0028,0008) | Number of Frames | Must be 1 |
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

Two voxels connect when they share a face. Of two pieces of one size, `keep_largest` keeps the piece with the lowest voxel index.

`label_surface(map, label)` returns the boundary of a label as a closed triangle mesh. The mesh is in the volume frame, in meters. The surface passes halfway between a voxel inside the label and a voxel outside it.

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

Each pixel is a trilinear sample of the volume. A point outside the box of voxel centers takes the `outside` value, such as -1000 for air in CT. The result is a volume of one slice, placed on the plane, with the source's window and photometric interpretation. `voxel_point(p)` gives the voxel units of a patient-space point. It is the inverse of `patient_point`.

## Overlays

`overlay_labels(image, map, axis, index, opacity)` blends a color over each labeled pixel. The labels cycle through eight colors from `label_color`. `draw_measurement(image, axis, a, b, color)` draws the line between two points, with a small cross at each end.

## Verification

The tests check these results:

- A slice written by `encode_dicom` reads back with every element equal, in both transfer syntaxes.
- A 12-bit signed value masks and extends its sign: `0xF800` reads as -2048.
- A volume cut into slices, written, read and stacked gives the same values and spacing.
- `trilinear` is exact for a linear field.
- An oblique reformat of a linear field matches the field at every pixel.
- A uniform volume of opacity 0.25 per voxel, four voxels deep, passes `0.75^4` of the background.
- An isosurface of a linear ramp has the full iso color along the gradient, and the ambient light across it.
- An ellipsoid of 904.8 voxels labels 879 voxels, within four percent, with its centroid exact.
- One render with one, three and every core gives the same bytes.
- Four NIfTI files that nibabel 5.3.2 wrote read with nibabel's world points and values. They cover both byte orders, the sform, the qform with a flip, voxel sizes in microns, and gzip. `assets/nifti/make_nifti.py` makes them.
- A volume and a label map written as NIfTI, plain and in gzip, read back with the same values and placement.

The example labels the left ventricle of a 128-voxel phantom. It measures 77.9 mL. The ellipsoid of the ventricle holds 76.9 mL.

## Errors

Every function raises `Error` for input it cannot use. The table gives the cases.

| Case | Functions |
|---|---|
| A file is not Part 10, or ends inside an element | `parse_dicom`, `read_dicom` |
| A transfer syntax is compressed or big endian | `parse_dicom`, `read_dicom` |
| An image is not one frame of one grayscale sample | `parse_dicom`, `read_dicom` |
| A grid is empty or holds more than 2^28 voxels | `ImageVolume`, `shepp_logan` |
| A file is not single-file NIfTI-1, or its datatype, unit or axes are not supported | `parse_nifti`, `read_nifti` |
| Slices disagree, share a position or are not evenly spaced | `stack_slices` |
| An index is outside the grid | `get`, `set`, `region_grow`, `render_slice` |
| A label is not from 0 to 255, or is the background where a region is needed | Label functions |
| A window, step, ambient light or crop is out of range | `render_volume`, `render_slice` |

## Limits

- The reader takes uncompressed little-endian grayscale images only. It does not read color, multiframe, JPEG, JPEG 2000 or RLE files.
- The reader does not read a file that has no preamble.
- The NIfTI reader does not read NIfTI-2, a header and image pair, complex or color voxels, or sheared axes.
- A stack refuses a gantry tilt and slices that are not evenly spaced. It does not resample them.
- The ray caster runs on the CPU only. It has no GPU path and no parity test.
- Rendering uses the volume frame. It does not apply the patient orientation.
- Connectivity is by faces only. Edge and corner neighbors do not connect.
- The colors of a transfer function are display values. They are not linear light.

## References

- NEMA PS3.5, "Data Structures and Encoding", sections 7.1 and 7.5, and annex A.
- NEMA PS3.3, "Information Object Definitions", sections C.7.6.2 and C.11.2.1.
- NEMA PS3.10, "Media Storage and File Format", section 7.
- Cox and others, "A (sort of) new image data format standard: NIfTI-1", 2004, and the header `nifti1.h`.
- Shepp and Logan, "The Fourier reconstruction of a head section", 1974.
- Toft, "The Radon Transform: Theory and Implementation", 1996.
- Levoy, "Display of surfaces from volume data", 1988.
- Engel and others, "Real-Time Volume Graphics", 2006.
