# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write the Hessian eigenvalues and the Frangi vesselness of a synthetic
volume, with scikit-image.

    mojo run -I . tools/make_vesselness.mojo
    cd assets/vesselness && python3 make_vesselness.py > vesselness_expected.txt

Run it with numpy 2.5.4, scipy 1.18.1 and scikit-image 0.26.
`tools/make_vesselness.mojo` writes the volume, `volume.txt`: 20 by 18 by
16 voxels of 1 mm, with x the fastest axis, in 32-bit values as a volume
stores them. It holds:

- a bright tube along (1, 0.5, 0.25) through (8, 8, 6) mm, of height 100
  and a Gaussian profile of 1.2 mm;
- a bright blob at (14, 4, 10) mm, of height 80 and 2 mm;
- a bright plate at z = 13 mm, of height 40 and 1 mm, where x is 12 mm or
  more.

The tests read the same volume. The lines are:

- `eigen sigma at l1 l2 l3`: the eigenvalues of scikit-image's
  `hessian_matrix` with `use_gaussian_derivatives=True`, from
  `hessian_matrix_eigvals`, sorted by magnitude, at the voxel of index
  `at`, for sigma 1 and 2 voxels.
- `anisotropic at l1 l2 l3`: the same with sigma 2 mm on voxels of 1, 1
  and 2 mm, as per-axis sigmas in voxels, in units of mm^-2.
- `frangi at v`: `frangi` with sigmas 1, 2 and 3, alpha 0.5, beta 0.5,
  and `black_ridges=False`, for bright vessels.
- `total sum max`: the sum and the largest value of the vesselness.
"""

import numpy
from skimage.feature import hessian_matrix, hessian_matrix_eigvals
from skimage.filters import frangi

NX, NY, NZ = 20, 18, 16


def volume():
    # Each line is the shortest text of a 32-bit value.
    values = numpy.loadtxt("volume.txt", dtype=numpy.float32)
    return values.astype(numpy.float64).reshape(NZ, NY, NX)


def sorted_eigen(h):
    e = hessian_matrix_eigvals(h)
    return numpy.take_along_axis(e, abs(e).argsort(0), 0)


def words(values):
    return " ".join(repr(float(v)) for v in values)


image = volume()
probes = list(range(0, NX * NY * NZ, 97)) + [6 * NX * NY + 8 * NX + 8, 10 * NX * NY + 4 * NX + 14]
for sigma in (1.0, 2.0):
    e = sorted_eigen(hessian_matrix(image, sigma, mode="reflect", use_gaussian_derivatives=True))
    flat = e.reshape(3, -1)
    for at in probes:
        print("eigen", words([sigma, at] + list(flat[:, at])))
# Voxels of 1, 1 and 2 mm along x, y and z: sigma 2 mm is (1, 2, 2) voxels
# along (z, y, x). Each derivative in mm divides by the two spacings.
h = hessian_matrix(image, (1.0, 2.0, 2.0), mode="reflect", use_gaussian_derivatives=True)
spacing = (2.0, 1.0, 1.0)
pairs = [(a, b) for a in range(3) for b in range(a, 3)]
h = [h[n] / (spacing[a] * spacing[b]) for n, (a, b) in enumerate(pairs)]
flat = sorted_eigen(h).reshape(3, -1)
for at in probes:
    print("anisotropic", words([at] + list(flat[:, at])))
v = frangi(image, sigmas=[1, 2, 3], alpha=0.5, beta=0.5, black_ridges=False, mode="reflect")
for at in probes:
    print("frangi", words([at, v.reshape(-1)[at]]))
print("total", words([v.sum(), v.max()]))
