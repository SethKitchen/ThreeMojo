# WarpFactory parity data

This folder holds reference values from the original WarpFactory, which
`tests/test_warp_parity.mojo` compares with the port in `extensions/warp/`.

GNU Octave 8.4.0 ran WarpFactory at commit `03b10cb` with `parity.m`. The
values are in `reference.txt`. `tests/_warpfactory_reference.mojo` holds the
same lines, so that the test reads no file.

## Regenerate the values

1. Install GNU Octave. On Ubuntu, run `apt-get install octave`.
2. Clone WarpFactory and check out commit `03b10cb`.
3. Run `WARPFACTORY=/path/to/WarpFactory octave-cli --no-gui docs/warpfactory-parity/parity.m`.
4. Copy the new `reference.txt` into the string in `tests/_warpfactory_reference.mojo`.

The comments at the top of `parity.m` give the cases and the line format.

## Shims

Octave lacks some MATLAB functions that WarpFactory calls. The files in
`shims/` stand in for them. Each one changes no math.

| File | Why |
|---|---|
| `isgpuarray.m`, `gpuArray.m`, `gather.m` | Octave has no Parallel Computing Toolbox. These say "no GPU" and pass arrays through. |
| `smooth.m` | Octave has no Curve Fitting Toolbox. It handles only a width of 1, which leaves the data unchanged. Any other width raises an error. |
| `pagemtimes.m` | Octave 8 has no `pagemtimes`. This one multiplies page by page. |
| `verifyTensor.m` | A copy of WarpFactory's file. Octave 8 has no `string` class, so `string(...)` became `char(...)`. |
| `getEulerianTransformationMatrix.m` | A copy. Octave 8's `sum` has no `'all'` option, in a line that only warns. |
| `getEvenPointsOnSphere.m` | A copy. `zeros(..., 'gpuArray')` became `gpuArray(zeros(...))`. |

## Known differences

- The smoothing of the warp shell is not checked. With a width of 1 it does nothing, in MATLAB and here.
- Octave builds `linspace` from both ends, and MATLAB does not. This moves the warp shell's values by about 5 parts in 10¹³.
- WarpFactory's second-order solver uses G = 6.674e-11 and c = 2.99792e8. The test scales those values to the exact constants.
- WarpFactory lowers the Eulerian tensor with the coordinate metric for the null and weak conditions. The test checks that behavior with its own lowering, and checks the port's corrected values separately.
