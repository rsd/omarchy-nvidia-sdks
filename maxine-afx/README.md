# maxine-afx: the Maxine Audio Effects SDK as a local package

This recipe builds `maxine-afx-sdk-local`, a local Arch package of the NVIDIA Maxine Audio Effects (AFX) SDK 3.0.0 for Linux, from your own download. Several projects on the machine can share the package. You need this page to build the package by hand. [`scripts/setup.sh`](../scripts/setup.sh) does the same steps with questions ([../INSTALL.md](../INSTALL.md)).

You download the SDK yourself, after accepting NVIDIA's licence ([../docs/download.md](../docs/download.md#maxine-audio-effects-sdk)). This directory holds only the recipe ([`PKGBUILD`](PKGBUILD)). The built package contains NVIDIA software: keep it on your own machine and never share or upload it.

The package version is the SDK's full version, `3.0.0.12` (from its `version.h`). NGC tags the downloads with the first three parts, `3.0.0`.

## Before you start

- Your download of the SDK from NGC, or an SDK tree ([Downloading](#downloading), [Source layouts](#source-layouts)).
- Your GPU's architecture, for example `sm_120` ([GPU architectures](#gpu-architectures)).
- Free disk space: the build copies the tree into `src/` and `pkg/` and writes the package file. On btrfs (or another filesystem with reflinks) the copies share their data. Otherwise plan for about three times the tree's size, plus the installed tree. `makepkg -c` removes `src/` and `pkg/` after the build.
- `makepkg`, `fakeroot` and `bsdtar` ([../INSTALL.md](../INSTALL.md#before-you-start)).

## Build and install

From this directory:

```sh
./configure.sh --src ~/Downloads/maxine/afx-sdk --archs sm_120 --features all --write
PKGEXT=.pkg.tar makepkg -f
# or without selection.conf, exactly the features a consumer needs:
MAXINE_AFX_SRC=~/Downloads/maxine/afx-sdk MAXINE_AFX_FEATURES=denoiser,studio_voice makepkg -f
```

With the four 48k features and `sm_120` models the SDK tree is about 3.8 GiB (the models are about 1.5 GiB of it), and the package is about 3.75 GiB uncompressed. `PKGEXT=.pkg.tar` in front of `makepkg` skips a slow compression.

Install the package yourself:

```sh
sudo pacman -U maxine-afx-sdk-local-*-x86_64.pkg.tar*
```

## Check that it works

```sh
pacman -Ql maxine-afx-sdk-local | head
ls /opt/nvidia/maxine/afx/features/denoiser/models/sm_120
(set -a; . /usr/share/maxine-afx/maxine-afx.env; set +a
 ldd /opt/nvidia/maxine/afx/nvafx/lib/libnv_audiofx.so | grep 'not found')
```

With the environment file applied, the `ldd` command prints nothing. Use a feature and architecture your package holds in the second command. More in [../docs/usage.md](../docs/usage.md#check-the-afx-installation).

## Uninstall

```sh
sudo pacman -R maxine-afx-sdk-local
```

## What the package installs

| Path | Content |
|---|---|
| `/opt/nvidia/maxine/afx/` | the SDK tree as NVIDIA lays it out (`nvafx/lib`, `nvafx/include`, `features/<feature>/{lib,include,licenses,models}`, `external/cuda/lib`, `licenses/`, `samples/`, `version.h`) |
| `/usr/lib/maxine-afx/os-release-shim.so` | the os-release shim, a compatibility shim for distributions the SDK does not list; NVIDIA does not support this configuration ([../tools/os-release-shim/](../tools/os-release-shim/README.md)) |
| `/usr/lib/maxine-afx/fake-os-release` | the replacement `os-release` (Ubuntu 24.04) |
| `/usr/share/maxine-afx/maxine-afx.env` | the environment file a consumer loads ([../docs/usage.md](../docs/usage.md)) |
| `/usr/share/licenses/maxine-afx-sdk-local/` | links to the SDK's licence files (the SDK's agreements, the models' licence, the third-party notices), and this repository's licence (the shim) |
| `/usr/share/doc/maxine-afx-sdk-local/usage.md` | how a project uses the package |

Nothing goes under `/etc`, and nothing sets `LD_LIBRARY_PATH` or `LD_PRELOAD` globally. The SDK bundles CUDA 12.8, cuDNN 9.7 and TensorRT 10.9 in `external/cuda/lib`, and they would shadow the system's for every program. The feature libraries read `/etc/os-release`, so the shim is installed alongside, inactive until a consumer preloads it on its own program.

### Models and the environment file

Each feature's models are in `features/<feature>/models/sm_<N>/`, the models of every sample rate of that architecture side by side, as NVIDIA's `features/download_features.sh` installs them. Like that script, the build adds a relative link without the trailing build number to each model (`denoiser_48k.trtpkg -> denoiser_48k_10752.trtpkg`), so a consumer can name a model without knowing that number. The models' `.md5` files are checked during the build and not installed, as that script does.

The SDK does not search for models: an application passes the model's path to the effect (its `model_path` parameter). The environment file therefore gives the directory to build that path from instead of a single model directory:

| Key | Value |
|---|---|
| `MAXINE_AFX_ROOT` | `/opt/nvidia/maxine/afx` |
| `MAXINE_AFX_FEATURES_DIR` | `/opt/nvidia/maxine/afx/features`; a model is `$MAXINE_AFX_FEATURES_DIR/<feature>/models/sm_<N>/<model>.trtpkg` |
| `MAXINE_AFX_LIBRARY_PATH`, `LD_LIBRARY_PATH` | `nvafx/lib`, one `features/<feature>/lib` per packaged feature (sorted by name), then the optional `features/speaker_focus/lib` and `features/superres/lib` (even if absent, unless already packaged), `external/cuda/lib` |
| `MAXINE_AFX_OS_RELEASE_SHIM` | `/usr/lib/maxine-afx/os-release-shim.so`, to put in `LD_PRELOAD` of the final program |
| `MAXINE_OS_RELEASE` | `/usr/lib/maxine-afx/fake-os-release`, read by the shim |
| `MAXINE_AFX_FEATURES`, `MAXINE_AFX_ARCHS`, `MAXINE_AFX_RATES` | informational: what went in, comma-separated, for example `denoiser,studio_voice`, `sm_120`, `48k` |

The library path is needed: `libnv_audiofx.so` loads the feature libraries, and their own search path does not reach `external/cuda/lib`.

## Downloading

[`download.sh`](download.sh) fetches the SDK from NGC with your own, configured NGC CLI. It never reads `~/.ngc` or handles an API key, and never runs NVIDIA's `download_features.sh`. It detects your GPU architecture, probes NGC for the sizes, prints a table, asks for confirmation, downloads only what is missing, verifies each item against the size NGC reports and retries failures:

```sh
./download.sh                     # preset broadcast: denoiser, dereverb, dereverb_denoiser, studio_voice at 48k
./download.sh --dry-run           # table and commands only, nothing downloaded
./download.sh --preset all --yes  # the ten effects that are not Early Access, no question
./download.sh --features denoiser-16k,superres-16k_to_48k --archs sm_120
./download.sh --list              # what NGC offers, with sizes
./download.sh --yes --build       # download, then configure.sh --write and makepkg -f; never installs
```

An effect is named as NVIDIA's script names it, `<feature>-<rate>`. The NGC items are:

| Item | NGC (`ngc registry ... download-version`) | Directory it creates |
|---|---|---|
| core | resource `nvidia/maxine/maxine_linux_audio_effects_sdk:3.0.0` | `maxine_linux_audio_effects_sdk_v3.0.0/` |
| feature library | model `nvidia/maxine/afx_<feature>:3.0.0-lib` | `afx_<feature>_v3.0.0-lib/` |
| models | model `nvidia/maxine/afx_<feature>:3.0.0-<rate>-sm<N>` | `afx_<feature>_v3.0.0-<rate>-sm<N>/` |

The default download directory, and the default source of `configure.sh`, is `~/Downloads/maxine/afx-sdk`.

## Source layouts

`MAXINE_AFX_SRC` (default: this directory) may hold either:

1. **An SDK tree**: the directory itself, or its `Audio_Effects_SDK/` subdirectory, contains `nvafx/lib/libnv_audiofx.so`, `version.h`, `features/<feature>/lib/*.so` and `features/<feature>/models/sm_<N>/*.trtpkg`. An example is a previous install made with NVIDIA's own script.
2. **An NGC download**, the directories as `ngc ... download-version` creates them:
   - `maxine_linux_audio_effects_sdk_v3.0.0/NVIDIA_AFX_SDK_Linux_3.0.0.12.tar.gz` (or the bare tarball);
   - `afx_<feature>_v3.0.*-lib/*.tar.gz` for each feature;
   - `afx_<feature>_v3.0.*-<rate>-sm<N>/` for each sample rate and architecture.

   A feature's MAJOR.MINOR must equal the SDK's (3.0). Any other `afx_*_v*` entry stops the build.

Keep one layout per directory. A source holding both an SDK tree and NGC downloads stops the build, which asks you to move one away or to point `MAXINE_AFX_SRC` at the one you mean.

**The download is data, never executed.** [`assemble.sh`](assemble.sh) enforces these rules:

- It lists every archive's member names before extracting it, and refuses an absolute name or a `..` component.
- A symbolic link to a directory, or to an existing file outside the tree, stops the build. Dangling links are kept as shipped and counted.
- Each models directory used must hold only regular files, at least one `.trtpkg`, and each `<model>.trtpkg.md5` next to its model. The copied model is hashed with `md5sum`, and a mismatch stops the build (a corrupted or interrupted download).
- Other files in a models directory are not copied from a download, and are kept as they are in an SDK tree. A note names them in both cases.
- Two files of the same name for one feature and architecture must be identical.

The source is never modified. `assemble.sh` builds the tree and checks it: the version header, the core library and header, one library per feature, and models for every selected architecture. It ends with a summary: the mode, the version, the features, the architectures and sample rates packaged, the number and size of the model files per architecture, and the checksums verified.

## Build inputs

| Variable | Default | Meaning |
|---|---|---|
| `MAXINE_AFX_SRC` | this directory | where the download or tree is |
| `MAXINE_AFX_ARCHS` | `sm_120` (`_maxine_archs` in the PKGBUILD) | GPU architectures whose models are packaged: `sm_120`, `sm120` or `120`, space- or comma-separated, for example `"sm_120 sm_89"`; or `all`, alone |
| `MAXINE_AFX_FEATURES` | `all` | `all`: every feature present is packaged. A list, space- or comma-separated, for example `denoiser,studio_voice`: exactly those are packaged, and the build fails when one of them is missing |

Each value comes from the environment variable of that name when it is set and not empty, else from `selection.conf` in this directory, else from the default. `prepare()` prints every value and where it came from (`environment`, `selection.conf` or `default`).

Sample rates are not an input: every rate present for the selected features and architectures is packaged, and `MAXINE_AFX_RATES` records them. To leave a rate out, leave its download out of the source.

### Choosing with configure.sh

[`configure.sh`](configure.sh) shows what a download holds and saves the selection in `selection.conf`. It reads the source without network access, never runs `ngc`, NVIDIA's scripts or `sudo`, and extracts nothing:

```sh
./configure.sh --src ~/Downloads/maxine/afx-sdk            # what is present, what the SDK offers, the current selection
./configure.sh --src ~/Downloads/maxine/afx-sdk --archs sm_120 --features all --write
./configure.sh --show                                      # print the current selection.conf
./configure.sh --detect-gpu                                # opt-in: asks nvidia-smi for the architecture
```

- Without `--write` it prints:
  - each feature present with the architectures and sample rates of its models;
  - the effects NVIDIA offers for 3.0.0 with their rates, and the architectures NVIDIA's download script has models for;
  - the current selection, and the commands to change it or to fetch more.
- `--write` validates the selection against what is present: a feature, or an architecture a selected feature lacks at one of its rates, is an error that names the `ngc` command fetching it. It then replaces `selection.conf` atomically (a temporary file, then a rename) and prints the result. An option left out keeps the value of the current `selection.conf`, else the default. `--archs` or `--features` without `--write` only validates.
- `--src` defaults to `$MAXINE_AFX_SRC`, else the `MAXINE_AFX_SRC` of the current `selection.conf`, else `~/Downloads/maxine/afx-sdk`. The output says which one it used. `assemble.sh --scan` reads the source, so the same layout rules and refusals apply as in the build.
- `--detect-gpu` runs `nvidia-smi --query-gpu=name,compute_cap --format=csv,noheader` and suggests the `sm_` value. Nothing else runs `nvidia-smi`: the query wakes a sleeping discrete GPU.

### selection.conf

`selection.conf` is git-ignored: it holds a path on your machine. It contains comment lines and exactly these keys:

```
MAXINE_AFX_SRC=/home/you/Downloads/maxine/afx-sdk
MAXINE_AFX_ARCHS=sm_120
MAXINE_AFX_FEATURES=all
```

The PKGBUILD reads it in `prepare()` only, so `makepkg --printsrcinfo` does not depend on it. [`selection.sh`](selection.sh) parses it as `KEY=value` lines and never sources or executes it. These stop the build with the line number:

- an unknown key, or a line that is not `KEY=value`;
- a key given twice, or an empty value;
- a value containing `$`, a backtick, a quote or a control character;
- a `MAXINE_AFX_SRC` that is not an absolute path.

### GPU architectures

An architecture is the GPU's compute capability without the dot. The build does not detect it: `nvidia-smi` would wake a sleeping discrete GPU. Look it up once, by hand (or with `./configure.sh --detect-gpu`):

```sh
nvidia-smi --query-gpu=compute_cap --format=csv,noheader   # 12.0 -> sm_120
```

`all` packages every architecture found in the source. Without it, every selected feature that has models must have them for every selected architecture, at every sample rate it has models for. The build stops otherwise, naming the feature, the rate, the architecture and the NGC tag. A source without any models only warns.

### Features

The features present are, in an SDK tree, every `features/<feature>/` with `lib/*.so`, and in a download every `afx_<feature>_v3.0.*-lib/*.tar.gz`. With `MAXINE_AFX_FEATURES=all` every one of them is packaged. With a list, exactly the listed ones are packaged (the build summary lists the others as "present, not selected"), and a feature left out is neither unpacked nor are its models copied. Studio Voice is one feature with two libraries, high quality and low latency, and a mic profile model used by the low latency effect.

To add a feature later, download it into the same directory, run `./configure.sh` again and rebuild. Nothing in the PKGBUILD changes.

### One package

The result is one package, `maxine-afx-sdk-local`, holding whatever was downloaded. Split packages per feature were rejected for the same reason as in [../maxine-vfx/](../maxine-vfx/README.md#one-package): makepkg needs the package names when it parses the PKGBUILD, while the feature set is only known after reading the download.

## Tests

The tests use fake files with the SDK's names, a fake `ngc` and stubs. They need no GPU, no network and no NVIDIA download, and write only under `mktemp`:

```sh
tests/assemble-test.sh    # assemble.sh: both layouts, checksums, archives, links, --scan
tests/configure-test.sh   # configure.sh and selection.sh
tests/download-test.sh    # download.sh against a fake ngc
tests/pkgbuild-test.sh    # makepkg builds of the PKGBUILD (needs makepkg, fakeroot, bsdtar, a C compiler)
```
