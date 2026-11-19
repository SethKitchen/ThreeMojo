# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the NIfTI-1 fixtures with nibabel, the reference Python reader.

    python3 make_nifti.py > expected.txt

Run it with nibabel 5.3.2 and numpy 2.1.3. `tests/test_imaging_nifti.mojo`
reads the files and compares its points and values with these. Each
fixture holds the value i + 10 j + 100 k at voxel (i, j, k). The
script prints the world point of voxel (1, 2, 1) of each file, in the
file's spatial unit, and nibabel's scaled value there. The point is
nibabel's affine, except for the file with no qform and no sform: there
it is the standard's method 1.
"""

import nibabel
import numpy

SHAPE = (4, 3, 2)


def ramp(dtype):
    i, j, k = numpy.indices(SHAPE)
    return (i + 10 * j + 100 * k).astype(dtype)


def turn_z(degrees):
    a = numpy.radians(degrees)
    return numpy.array(
        [[numpy.cos(a), -numpy.sin(a), 0], [numpy.sin(a), numpy.cos(a), 0], [0, 0, 1]]
    )


def report(name):
    image = nibabel.load(name)
    point = image.affine @ numpy.array([1, 2, 1, 1])
    if image.header["qform_code"] == 0 and image.header["sform_code"] == 0:
        # nibabel's affine follows Analyze here; NIfTI's method 1 does not
        # center or flip.
        point = numpy.array(image.header.get_zooms()) * numpy.array([1, 2, 1])
    value = image.get_fdata()[1, 2, 1]
    print(name, " ".join(repr(float(x)) for x in point[:3]), repr(float(value)))


def write_raw(name, header, data):
    """Write a header and its data exactly as set, with no rescaling."""
    header["vox_offset"] = 352
    header["magic"] = b"n+1"
    with open(name, "wb") as out:
        header.write_to(out)
        nibabel.volumeutils.array_to_file(
            data, out, header.get_data_dtype(), offset=352, order="F"
        )


# Little endian int16 with an sform turned 90 degrees about z, a rescale
# and a display range.
affine = numpy.eye(4)
affine[:3, :3] = turn_z(90) @ numpy.diag([2.0, 3.0, 4.0])
affine[:3, 3] = [10.0, -20.0, 30.0]
header = nibabel.Nifti1Header()
header.set_data_shape(SHAPE)
header.set_data_dtype(numpy.int16)
header.set_sform(affine, code=1)
header.set_qform(None, code=0)
header.set_slope_inter(0.5, -10.0)
header["cal_min"] = 0
header["cal_max"] = 100
header.set_xyzt_units("mm")
write_raw("le_sform.nii", header, ramp(numpy.int16))

# Big endian float32 with only a qform: turned 30 degrees about z, with
# k flipped by qfac.
affine = numpy.eye(4)
affine[:3, :3] = turn_z(30) @ numpy.diag([1.5, 2.5, -0.5])
affine[:3, 3] = [-5.0, 6.0, 7.0]
header = nibabel.Nifti1Header(endianness=">")
image = nibabel.Nifti1Image(ramp(numpy.float32), affine, header)
image.header.set_qform(affine, code=1)
image.header.set_sform(None, code=0)
image.header.set_xyzt_units("mm")
nibabel.save(image, "be_qform.nii")

# Signed bytes placed by voxel size alone, in microns: the standard's
# method 1, x = pixdim[1] i and so on.
header = nibabel.Nifti1Header()
header.set_data_shape(SHAPE)
header.set_data_dtype(numpy.int8)
header.set_zooms((500.0, 250.0, 1000.0))
header.set_qform(None, code=0)
header.set_sform(None, code=0)
header.set_xyzt_units("micron")
write_raw("pixdim_micron.nii", header, ramp(numpy.int8) - 60)

# Unsigned byte labels inside gzip.
labels = (ramp(numpy.uint8) % 7).astype(numpy.uint8)
image = nibabel.Nifti1Image(labels, numpy.diag([1.0, 1.0, 1.0, 1.0]))
image.header.set_intent("label")
nibabel.save(image, "labels.nii.gz")

for name in ["le_sform.nii", "be_qform.nii", "pixdim_micron.nii", "labels.nii.gz"]:
    report(name)
