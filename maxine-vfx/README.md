# maxine-vfx: the Maxine Video Effects SDK as a local package

This recipe builds `maxine-vfx-sdk-local`, a local Arch package of the NVIDIA Maxine Video Effects SDK 1.3.0.0, from your own download. Several projects on the machine can share the package. You need this page to build the package by hand. [`scripts/setup.sh`](../scripts/setup.sh) does the same steps with questions ([../INSTALL.md](../INSTALL.md)).

You download the SDK yourself, after accepting NVIDIA's licence ([../docs/download.md](../docs/download.md)). This directory holds only the recipe ([`PKGBUILD`](PKGBUILD)). The built package contains NVIDIA software: keep it on your own machine and never share or upload it.

## Before you start

- Your download of the SDK from NGC, or an SDK tree ([Downloading](#downloading), [Source layouts](#source-layouts)).
- Your GPU's architecture, for example `sm_120` ([GPU architectures](#gpu-architectures)).
- Free disk space: the SDK tree is about 4.4 GiB (4.71 GiB with all eight features). The build copies it into `src/` and `pkg/` and writes the package file. On btrfs (or another filesystem with reflinks) the copies share their data. Otherwise plan for about three times the tree's size, plus the installed tree. `makepkg -c` removes `src/` and `pkg/` after the build.
- `makepkg`, `fakeroot` and `bsdtar` ([../INSTALL.md](../INSTALL.md#before-you-start)).

## Build and install

From this directory:

```sh
./configure.sh --src ~/Downloads/maxine --archs sm_120 --features all --write
makepkg -f
```

Other ways to give the same inputs:

```sh
# without selection.conf, from an existing SDK tree:
MAXINE_VFX_SRC=~/.local/opt/maxine/VideoFX makepkg -f
# from an NGC download, for two architectures:
MAXINE_VFX_SRC=~/Downloads/maxine MAXINE_VFX_ARCHS="sm_120 sm_89" makepkg -f
# exactly the features a consumer needs (the build fails when one is missing):
MAXINE_VFX_SRC=~/Downloads/maxine MAXINE_VFX_FEATURES=nvvfxgreenscreen,nvvfxbackgroundblur makepkg -f
```

The package is about 4.4 GiB with green screen and background blur for one architecture. With all eight features and `sm_120` models it is about 4.7 GiB: the tree is 5,054,183,158 bytes (4.71 GiB), and the five features outside the default add 326,922,413 bytes (about 312 MiB) to the download. `PKGEXT=.pkg.tar` in front of `makepkg` skips a slow compression.

Install the package yourself:

```sh
sudo pacman -U maxine-vfx-sdk-local-*-x86_64.pkg.tar*
```

## Check that it works

```sh
pacman -Ql maxine-vfx-sdk-local | head
(set -a; . /usr/share/maxine-vfx/maxine-vfx.env; set +a
 ldd /opt/nvidia/maxine/videofx/lib/libVideoFXLocal.so | grep 'not found')
```

With the environment file applied, the `ldd` command prints nothing. To run the effects on the GPU, build and run the probe in [../tools/maxine-probe/](../tools/maxine-probe/README.md). Problems with a running program are in [../docs/usage.md](../docs/usage.md#troubleshooting).

## Uninstall

```sh
sudo pacman -R maxine-vfx-sdk-local
```

## What the package installs

| Path | Content |
|---|---|
| `/opt/nvidia/maxine/videofx/` | the SDK tree (`lib/`, `lib/models/`, `features/`, `include/`, `external/cuda`, `external/tensorrt`, `share/`) |
| `/usr/lib/maxine-vfx/os-release-shim.so` | the os-release shim, a compatibility shim for distributions the SDK does not list; NVIDIA does not support this configuration ([../tools/os-release-shim/](../tools/os-release-shim/README.md)) |
| `/usr/lib/maxine-vfx/fake-os-release` | the replacement `os-release` (Ubuntu 24.04) |
| `/usr/share/maxine-vfx/maxine-vfx.env` | the environment file a consumer loads ([../docs/usage.md](../docs/usage.md)) |
| `/usr/share/licenses/maxine-vfx-sdk-local/` | links to the SDK's licence files, and this repository's licence (the shim) |
| `/usr/share/doc/maxine-vfx-sdk-local/usage.md` | how a project uses the package |

Nothing goes under `/etc`, and nothing sets `LD_LIBRARY_PATH` or `LD_PRELOAD` globally: the bundled CUDA 12 and TensorRT 10 would shadow the system's for every program.

The selected features are packaged (by default every feature found in the source), with the models of the selected GPU architectures. No engine cache directory is created. The environment file records what went in: `MAXINE_VFX_FEATURES` and `MAXINE_VFX_ARCHS` (comma-separated, for example `nvvfxbackgroundblur,nvvfxgreenscreen` and `sm_120`), and one `features/<feature>/lib` entry per feature on the library path.

## Downloading

[`download.sh`](download.sh) fetches the SDK from NGC with your own, configured NGC CLI. It detects your GPU architecture, probes NGC for the sizes, prints a table, asks for confirmation, downloads only what is missing, verifies each item and retries failures:

```sh
./download.sh                     # preset broadcast (green screen, background blur, denoising) for your GPU
./download.sh --dry-run           # table and commands only, nothing downloaded
./download.sh --preset all --yes  # all eight features, no question
./download.sh --list              # what NGC offers, with sizes
./download.sh --yes --build       # download, then configure.sh --write and makepkg -f; never installs
```

The options (`--dest`, `--archs`, `--preset`, `--features`, `--version`, `--retries`, `--yes`, `--dry-run`, `--build`, `--list`), the account setup and the manual `ngc` commands are in [../docs/download.md](../docs/download.md).

## Source layouts

`MAXINE_VFX_SRC` (default: this directory) may hold either:

1. **An SDK tree**: the directory itself, or its `VideoFX/` subdirectory, contains `lib/libVideoFX.so`, `share/videofx_version.h`, `features/<feature>/lib/*.so` and `lib/models/*.trtpkg`. An example is a previous install under `~/.local/opt/maxine/VideoFX`.
2. **An NGC download**, the directories as `ngc ... download-version` creates them:
   - `vfx_sdk_core_v1.3.0.0_linux/VFXSDK_linux_1.3.0.0.tgz` (or the bare `.tgz`);
   - `<feature>_v1.3.*_lib_linux/*.tar.gz` for each feature;
   - `<feature>_v1.3.*_models_linux_sm<N>/` for each feature with models and each architecture.

   A feature's MAJOR.MINOR must equal the SDK's (1.3).

Keep one layout per directory. A source holding both an SDK tree and NGC downloads stops the build, which asks you to move one away or to point `MAXINE_VFX_SRC` at the one you mean. Each models directory used must hold the model files directly inside (at least one, no subdirectories). A file name that appears in two models directories must have the same content in both.

**Symbolic links in the source.** A link to a directory, or to an existing file outside the tree, stops the build. It would put a link into your home directory in the package, and removing the engine cache through it would delete your own files. Dangling links are kept exactly as NVIDIA ships them: the 1.3.0.0 SDK has eight, seven of them cuDNN headers pointing into Debian's `/etc/alternatives`. The summary counts them.

The source is never modified. [`assemble.sh`](assemble.sh) builds the tree and checks it: the version header, the core libraries, one library per feature, and models for every selected architecture. It ends with a summary: the mode, the version, the features, the architectures packaged, and the number and size of the model files per architecture.

## Build inputs

| Variable | Default | Meaning |
|---|---|---|
| `MAXINE_VFX_SRC` | this directory | where the download or tree is |
| `MAXINE_VFX_ARCHS` | `sm_120` (`_maxine_archs` in the PKGBUILD) | GPU architectures whose models are packaged: `sm_120`, `sm120` or `120`, space- or comma-separated, for example `"sm_120 sm_89"`; or `all`, alone |
| `MAXINE_VFX_FEATURES` | `all` | `all`: every feature present is packaged. A list, space- or comma-separated, for example `nvvfxgreenscreen,nvvfxbackgroundblur`: exactly those are packaged, and the build fails when one of them is missing |

Each value comes from the environment variable of that name when it is set and not empty, else from `selection.conf` in this directory, else from the default. `prepare()` prints every value and where it came from (`environment`, `selection.conf` or `default`).

### Choosing with configure.sh

[`configure.sh`](configure.sh) shows what a download holds and saves the selection in `selection.conf`. It reads the source without network access, never runs `ngc`, NVIDIA's `install_feature.sh` or `sudo`, and extracts nothing:

```sh
./configure.sh --src ~/Downloads/maxine            # what is present, what the SDK offers, the current selection
./configure.sh --src ~/Downloads/maxine --archs sm_120 --features all --write
./configure.sh --show                              # print the current selection.conf
./configure.sh --detect-gpu                        # opt-in: asks nvidia-smi for the architecture
```

- Without `--write` it prints:
  - the features present in the source with the architectures of their models (in an SDK tree, model files are not tied to a feature, so the architectures are given for the tree as a whole);
  - the features the SDK 1.3 offers and the architectures that have 1.3.0.0 Linux models;
  - the current selection, and the commands to change it or to fetch more.
- `--write` validates the selection against what is present: a feature or architecture that is not there is an error that names the `ngc` command fetching it. It then replaces `selection.conf` atomically (a temporary file, then a rename) and prints the result. An option left out keeps the value of the current `selection.conf`, else the default. `--archs` or `--features` without `--write` only validates.
- `--src` defaults to `$MAXINE_VFX_SRC`, else the `MAXINE_VFX_SRC` of the current `selection.conf`, else `~/Downloads/maxine`. The output says which one it used. A path containing a newline is refused. `assemble.sh --scan` reads the source, so the same layout rules and refusals apply as in the build.
- `--detect-gpu` runs `nvidia-smi --query-gpu=name,compute_cap --format=csv,noheader` and suggests the `sm_` value. Nothing else runs `nvidia-smi`: the query wakes a sleeping discrete GPU.

### selection.conf

`selection.conf` is git-ignored: it holds a path on your machine. It contains comment lines and exactly these keys:

```
MAXINE_VFX_SRC=/home/you/Downloads/maxine
MAXINE_VFX_ARCHS=sm_120
MAXINE_VFX_FEATURES=all
```

The PKGBUILD reads it in `prepare()` only, so `makepkg --printsrcinfo` does not depend on it. [`selection.sh`](selection.sh) parses it as `KEY=value` lines and never sources or executes it. These stop the build with the line number:

- an unknown key, or a line that is not `KEY=value`;
- a key given twice, or an empty value;
- a value containing `$`, a backtick, a quote or a control character;
- a `MAXINE_VFX_SRC` that is not an absolute path.

### GPU architectures

An architecture is the GPU's compute capability without the dot. Which GPUs the SDK supports, and the architecture of each, are in [../docs/gpu-support.md](../docs/gpu-support.md). The build does not detect it: `nvidia-smi` would wake a sleeping discrete GPU. Look it up once, by hand (or with `./configure.sh --detect-gpu`):

```sh
nvidia-smi --query-gpu=compute_cap --format=csv,noheader   # 12.0 -> sm_120
```

`all` packages every architecture found in the source. In an SDK tree nothing is pruned. From an NGC download, every `<feature>_v1.3.*_models_linux_sm<N>/` directory is used. The summary lists the architectures found.

In an SDK tree, a model file belongs to an architecture when one of the underscore-separated fields of its name is a known SM number: `AIGS_288x512_120_m0.engine.trtpkg` is `sm_120`. Files of the other architectures are left out. A file whose name carries no SM number is kept and listed in a note. In a download, a file belongs to the architecture of its `models_linux_sm<N>` directory.

Each architecture adds the model packages of every selected feature that has models. In 1.3.0.0 Linux only green screen, denoising and relighting have them. For `sm_120` that is about 113 MiB, 3.7 MiB and 79 MiB. The sizes for every architecture are in [../docs/gpu-support.md](../docs/gpu-support.md#size-cost-per-architecture). Check a package before downloading it with `ngc registry model info`. The build summary prints the model size per architecture, so the cost is visible:

```sh
ngc registry model info nvidia/maxine/<feature>:<version>_models_linux_sm<N>
```

The build stops in two cases:

- a selected feature that has models in the download lacks them for a selected architecture (the message names the feature, the architecture and the NGC tag);
- a selected architecture has no model files although the source has models for others.

A source without any models only warns: a download of background blur alone is valid.

### Features

The features present in the source are, in an SDK tree, every `features/<feature>/` with `lib/*.so`, and in a download every `nvvfx*_v1.3.*_lib_linux/*.tar.gz`. With `MAXINE_VFX_FEATURES=all` every one of them is packaged. With a list, exactly the listed ones are packaged, and the others are left out (the build summary lists them as "present, not selected"). In a download a feature left out is not unpacked and its models are not copied. In an SDK tree its `features/<feature>/` directory is left out, but its model files cannot be told apart from the others' and stay in `lib/models` (a note says so). At least one feature must be packaged.

To add a feature later, download it (its library and, if it has them, its models for your architectures) into the same directory, run `./configure.sh` again and rebuild the package. Nothing in the PKGBUILD changes. The NGC names, sizes and commands are in [../docs/download.md](../docs/download.md#features).

When a packaged feature ships a non-empty `<Name>_dependencies.txt` that names a feature which is not present, or present but not selected, the build prints a warning and goes on.

### One package

The result is one package, `maxine-vfx-sdk-local`, holding whatever was downloaded. Split packages per feature were rejected:

- makepkg needs `pkgname=()` and the `package_<name>()` functions fixed when it parses the PKGBUILD (`makepkg --printsrcinfo` and `.SRCINFO` must not depend on the user's download), while the feature set is only known after reading the download.
- A hard-coded per-feature list would produce empty packages for absent features and need a PKGBUILD edit for each new NVIDIA feature.
