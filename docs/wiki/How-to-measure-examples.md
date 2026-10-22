# How to measure examples

`make bench-examples` times the examples listed in `bench/catalog.json`. It records compile time, run time and peak memory for ThreeMojo and for a three.js scene of the same size.

It also times the same programs and a standalone probe on the previous Mojo release when that compiler is present.

```bash
make bench-examples
```

The command writes the results for this kind of host and updates that host's tables on [Benchmarks](Benchmarks). A Linux host writes `bench/results-linux.json`. A Mac writes `bench/results-macos.json`. A run on one host does not change the tables of the other.

To rebuild the tables of one host from its results file, give the host:

```bash
sh tools/tool.sh .venv/bin/mojo bench_examples --from-results --platform macos
```

## What you need

You need the Mojo pin in `.venv/`. You need Node.js for the three.js scenes.

To compare the previous Mojo release, install that compiler in a second venv. Put it in `.venv-previous/` or `$HOME/.venvs/previous/`.

```bash
python3 -m venv $HOME/.venvs/previous
$HOME/.venvs/previous/bin/pip install mojo==1.1.0
```

Or set `MOJO_PREVIOUS` to the binary of the previous release. Pass `--skip-previous` to leave that comparison out.

The results file and the tables name each compiler by the version that `mojo --version` prints. A new Mojo release needs no change in the runner.

`make bench-examples` installs `bench/threejs` packages when `node_modules` is missing.

## Measure one example

```bash
sh tools/tool.sh .venv/bin/mojo bench_examples --only cube --merge
```

Use `--merge` to keep the other recorded rows. The host and toolchain metadata must match the previous file. The runner refuses a mismatch before it measures or writes results. The metadata records the version that `python3 --version` prints. It is empty when the host has no `python3`.

Without `--merge`, the command replaces that platform's results with the selected examples. Save the old file first if you need to keep it.

Each new row records its measurement date. Retained rows keep their dates. A legacy label uses an older aggregate date; its exact row date is unknown. A date does not identify a source revision. Keep the results file with the source revision that you tested.

## Read the numbers

Compile time is `mojo build` only. Run time is the fastest of three runs of the built binary, and of the Node process. Peak RSS is the kernel maximum resident set in MiB. The first launch of a freshly built binary on macOS pays a system check of several hundred milliseconds. One run is not enough.

ThreeMojo writes the image file. three.js draws the same width, height and frame count, and reads the pixels back. three.js does not encode an animated PNG.

The runner always times a `cpu-flat` fill. It also times WebGL 2 when `webgl-node` can open a context. On Linux, that context needs `libGLESv2` on the library path. On Ubuntu the package is `libgles2`. Without root, `make bench-examples` downloads the dispatcher into `bench/threejs/lib`. See [Benchmarks](Benchmarks#what-the-columns-measure).

On macOS, `webgl-node` opens the context with no extra package.
Pass `--skip-webgl` on a host with no GPU.

The pin is the Mojo release in `.venv/`. A second venv at `.venv-previous/` compiles the same sources with the previous release. A release that does not accept the sources is a refused compile. The probe is a standalone triangle fill that imports nothing from ThreeMojo.

The draw winner names the faster frame loop.
A gap under 10% is a tie.
See [Benchmarks](Benchmarks) for the recorded tables.
