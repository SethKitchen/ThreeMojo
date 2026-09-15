# How to install

This guide installs the pinned Mojo toolchain into a local `.venv`. Nothing is installed system-wide. At the end, `make check-cpu` passes.

## Requirements

| Platform | Support | Note |
|---|---|---|
| macOS | Yes | Apple Silicon only. Mojo does not support Intel Macs. |
| Linux | Yes | x86-64 and aarch64. |
| Windows | Through WSL 2 | Mojo has no native Windows build. |

You also need Python 3.9 or later, `git`, `make` and [`uv`](https://docs.astral.sh/uv/).

## macOS

1. Install the tools:

```bash
brew install uv
xcode-select --install
```

2. Clone and install the toolchain:

```bash
git clone https://github.com/SethKitchen/ThreeMojo.git
cd ThreeMojo
uv venv --prompt ThreeMojo
uv pip install "mojo==1.0.0"
```

## Linux

1. Install the tools. On Debian or Ubuntu:

```bash
sudo apt update && sudo apt install -y build-essential curl git
curl -LsSf https://astral.sh/uv/install.sh | sh
```

On Fedora, use `sudo dnf install -y make gcc git curl`. On Arch, use `sudo pacman -S --needed base-devel git curl`.

2. Clone and install the toolchain:

```bash
git clone https://github.com/SethKitchen/ThreeMojo.git
cd ThreeMojo
uv venv --prompt ThreeMojo
uv pip install "mojo==1.0.0"
```

## Windows

1. Open PowerShell as Administrator and install WSL 2:

```powershell
wsl --install -d Ubuntu
```

2. Reboot. Open the Ubuntu terminal.
3. Follow the Linux steps above.

Clone into the Linux filesystem, for example `~/ThreeMojo`. Do not clone into `/mnt/c/`. Builds across the filesystem boundary are much slower.

## Without uv

```bash
python3 -m venv .venv
.venv/bin/pip install "mojo==1.0.0"
```

## Verify

```bash
.venv/bin/mojo --version    # Mojo 1.0.0 (ed45d567)
make check-cpu
```

`make check-cpu` needs no GPU and no MAX. For the GPU backend, see [How to use the GPU backend](How-to-use-the-GPU-backend).

## Pinned versions

| Component | Version | Needed for |
|---|---|---|
| Mojo | `1.0.0` (`ed45d567`) | Everything |
| MAX | `26.5.0` | `render/gpu.mojo` and its tests only |
| Metal toolchain | Xcode component | GPU kernels on macOS |

The toolchain version is part of the build cache key. An upgrade invalidates every cached result.

## Editor setup

The Mojo language server does not read `-I .`. The repository ships `.vscode/settings.json` with `"mojo.lsp.includeDirs": ["."]`, which fixes the imports.

1. Install the Mojo extension by Modular.
2. Reload the window. The setting is read at language-server startup.

The value must be `"."`. The extension does not expand `${workspaceFolder}`.

## Activate the virtualenv

The Makefile calls `.venv/bin/mojo` by path. You do not need to activate the virtualenv. If you want to:

| Shell | Command |
|---|---|
| bash or zsh | `source .venv/bin/activate` |
| fish | `source .venv/bin/activate.fish` |
| PowerShell | `.venv\Scripts\Activate.ps1` |
