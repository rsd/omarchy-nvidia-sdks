# maxine-ar: the Maxine AR SDK as a local package

This recipe builds `maxine-ar-sdk-local`, a local Arch package of the NVIDIA Maxine AR SDK 1.2.0.0, from your own download. Several projects on the machine can share the package. You need this page to build the package by hand. [`scripts/setup.sh`](../scripts/setup.sh) does the same steps with questions ([../INSTALL.md](../INSTALL.md)).

You download the SDK yourself, after accepting NVIDIA's licence ([../docs/download.md](../docs/download.md)). This directory holds only the recipe ([`PKGBUILD`](PKGBUILD)). The built package contains NVIDIA software: keep it on your own machine and never share or upload it.

## Before you start

- Your download of the SDK from NGC, or an SDK tree ([Downloading](#downloading), [Source layouts](#source-layouts)).
- Your GPU's architecture, for example `sm_120` ([GPU architectures](#gpu-architectures)).
- Free disk space: the build copies the tree into `src/` and `pkg/` and writes the package file. On btrfs (or another filesystem with reflinks) the copies share their data. Otherwise plan for about three times the tree's size, plus the installed tree. `makepkg -c` removes `src/` and `pkg/` after the build.
- `makepkg`, `fakeroot` and `bsdtar` ([../INSTALL.md](../INSTALL.md#before-you-start)).

## Build and install

From this directory:

```sh
./configure.sh --src ~/Downloads/maxine/ar-sdk --archs sm_120 --features all --write
makepkg -f
```

Other ways to give the same inputs:

```sh
# without selection.conf, from an existing SDK tree:
MAXINE_AR_SRC=~/.local/opt/maxine/ARSDK makepkg -f
# from an NGC download, for two architectures:
MAXINE_AR_SRC=~/Downloads/maxine/ar-sdk MAXINE_AR_ARCHS="sm_120 sm_89" makepkg -f
# exactly the features a consumer needs (the build fails when one is missing):
MAXINE_AR_SRC=~/Downloads/maxine/ar-sdk MAXINE_AR_FEATURES=nvargazeredirection,nvarfaceboxdetection,nvarlandmarkdetection makepkg -f
```

With the four features eye contact, face box detection, landmark detection and face expressions, and `sm_120` models, the SDK tree is 4,757,681,936 bytes (4.43 GiB), of which 183,014,313 bytes (175 MiB) are `lib/models`. Most of the rest is the bundled CUDA and TensorRT libraries, which every selection carries. The uncompressed package is 4,758,773,760 bytes. `PKGEXT=.pkg.tar` in front of `makepkg` skips a slow compression.

Install the package yourself:

```sh
sudo pacman -U maxine-ar-sdk-local-*-x86_64.pkg.tar*
```

## Check that it works

```sh
pacman -Ql maxine-ar-sdk-local | head
ls /opt/nvidia/maxine/arsdk/lib/models
(set -a; . /usr/share/maxine-ar/maxine-ar.env; set +a
 ldd /opt/nvidia/maxine/arsdk/lib/libnvARPose.so | grep 'not found')
```

With the environment file applied, the `ldd` command prints nothing, and the model directory lists files for your architecture. The probe in [../tools/maxine-probe/](../tools/maxine-probe/README.md) checks the Video Effects SDK. It does not exercise this package. Problems with a running program are in [../docs/usage.md](../docs/usage.md#check-the-ar-installation).

## Uninstall

```sh
sudo pacman -R maxine-ar-sdk-local
```

## What the package installs

| Path | Content |
|---|---|
| `/opt/nvidia/maxine/arsdk/` | the SDK tree (`lib/`, `lib/models/`, `features/`, `include/`, `external/cuda`, `external/tensorrt`, `share/`) |
| `/usr/lib/maxine-ar/os-release-shim.so` | the os-release shim, a compatibility shim for distributions the SDK does not list; NVIDIA does not support this configuration ([../tools/os-release-shim/](../tools/os-release-shim/README.md)) |
| `/usr/lib/maxine-ar/fake-os-release` | the replacement `os-release` (Ubuntu 24.04) |
| `/usr/share/maxine-ar/maxine-ar.env` | the environment file a consumer loads ([../docs/usage.md](../docs/usage.md)) |
| `/usr/share/licenses/maxine-ar-sdk-local/` | links to the SDK's licence files, and this repository's licence (the shim) |
| `/usr/share/doc/maxine-ar-sdk-local/usage.md` | how a project uses the package |

Nothing goes under `/etc`, and nothing sets `LD_LIBRARY_PATH` or `LD_PRELOAD` globally: the bundled CUDA 12.8, cuDNN 9.7 and TensorRT 10.9 would shadow the system's for every program.

The selected features are packaged (by default every feature found in the source), with the models of the selected GPU architectures. No engine cache directory is created. The environment file records what went in: `MAXINE_AR_FEATURES` and `MAXINE_AR_ARCHS` (comma-separated, for example `nvarfaceboxdetection,nvargazeredirection,nvarlandmarkdetection` and `sm_120`), and one `features/<feature>/lib` entry per feature on the library path.

## Downloading

[`download.sh`](download.sh) fetches the SDK from NGC with your own, configured NGC CLI. It detects your GPU architecture, probes NGC for the sizes, prints a table, asks for confirmation, downloads only what is missing, verifies each item and retries failures:

```sh
./download.sh                     # preset broadcast (eye contact, face box and landmark detection) for your GPU
./download.sh --dry-run           # table and commands only, nothing downloaded
./download.sh --preset all --yes  # all seven documented features, no question
./download.sh --list              # the documented features on NGC, with sizes
./download.sh --yes --build       # download, then configure.sh --write and makepkg -f; never installs
```

The default destination is `~/Downloads/maxine/ar-sdk`, a directory of its own next to a Video Effects SDK download. The script uses the NGC CLI only. It never runs NVIDIA's `features/install_feature.sh`, which installs into `/usr/local/ARSDK` with `sudo`. The `broadcast` preset is eye contact (`nvargazeredirection`) with the two features its `nvARGazeRedirection_dependencies.txt` names. The feature list is the one in the SDK's `features/README.md` and Linux installation guide, which NVIDIA calls non-exhaustive. Another name can be given with `--features`.

The options (`--dest`, `--archs`, `--preset`, `--features`, `--version`, `--retries`, `--yes`, `--dry-run`, `--build`, `--list`), the account setup and the manual `ngc` commands are in [../docs/download.md](../docs/download.md).

## Source layouts

`MAXINE_AR_SRC` (default: this directory) may hold either:

1. **An SDK tree**: the directory itself, or its `ARSDK/` subdirectory, contains `lib/libnvARPose.so`, `share/arsdk_version.h`, `features/<feature>/lib/*.so` and `lib/models/*.trtpkg`. An example is a previous install under `~/.local/opt/maxine/ARSDK`.
2. **An NGC download**, the directories as `ngc ... download-version` creates them:
   - `ar_sdk_core_v1.2.0.0_linux/ARSDK_linux_1.2.0.0.tgz` (or the bare `.tgz`);
   - `<feature>_v1.2.*_lib_linux/*.tar.gz` for each feature;
   - `<feature>_v1.2.*_models_linux_sm<N>/` for each feature with models and each architecture.

   A feature's MAJOR.MINOR must equal the SDK's (1.2). The core resource directory also holds `ARSDK_triton_1.2.0.0.tgz`, the client for NVIDIA's Triton inference server. It is not packaged.

Keep one layout per directory. A source holding both an SDK tree and NGC downloads stops the build, which asks you to move one away or to point `MAXINE_AR_SRC` at the one you mean. Each models directory used must hold the model files directly inside (at least one, no subdirectories). A file name that appears in two models directories must have the same content in both.

**Symbolic links in the source.** A link to a directory, or to an existing file outside the tree, stops the build. It would put a link into your home directory in the package, and removing the engine cache through it would delete your own files. Dangling links are kept exactly as NVIDIA ships them and counted in the summary. The 1.2.0.0 core has none: its 80 links all point to files inside the tree.

The source is never modified. [`assemble.sh`](assemble.sh) builds the tree and checks it: the version header, the core libraries, one library per feature, and models for every selected architecture. It ends with a summary: the mode, the version, the features, the architectures packaged, and the number and size of the model files per architecture.

## Build inputs

| Variable | Default | Meaning |
|---|---|---|
| `MAXINE_AR_SRC` | this directory | where the download or tree is |
| `MAXINE_AR_ARCHS` | `sm_120` (`_maxine_archs` in the PKGBUILD) | GPU architectures whose models are packaged: `sm_120`, `sm120` or `120`, space- or comma-separated, for example `"sm_120 sm_89"`; or `all`, alone |
| `MAXINE_AR_FEATURES` | `all` | `all`: every feature present is packaged. A list, space- or comma-separated, for example `nvargazeredirection,nvarfaceboxdetection,nvarlandmarkdetection`: exactly those are packaged, and the build fails when one of them is missing |

Each value comes from the environment variable of that name when it is set and not empty, else from `selection.conf` in this directory, else from the default. `prepare()` prints every value and where it came from (`environment`, `selection.conf` or `default`).

### Choosing with configure.sh

[`configure.sh`](configure.sh) shows what a download holds and saves the selection in `selection.conf`. It reads the source without network access, never runs `ngc`, NVIDIA's `install_feature.sh` or `sudo`, and extracts nothing:

```sh
./configure.sh --src ~/Downloads/maxine/ar-sdk     # what is present, what the SDK offers, the current selection
./configure.sh --src ~/Downloads/maxine/ar-sdk --archs sm_120 --features all --write
./configure.sh --show                              # print the current selection.conf
./configure.sh --detect-gpu                        # opt-in: asks nvidia-smi for the architecture
```

- Without `--write` it prints:
  - the features present in the source with the architectures of their models (in an SDK tree, model files are not tied to a feature, so the architectures are given for the tree as a whole);
  - the features NVIDIA documents for the SDK 1.2 and the architectures NVIDIA's feature installer fetches 1.2.0.0 Linux models for;
  - the current selection, and the commands to change it or to fetch more.
- `--write` validates the selection against what is present: a feature or architecture that is not there is an error that names the `ngc` command fetching it. It then replaces `selection.conf` atomically (a temporary file, then a rename) and prints the result. An option left out keeps the value of the current `selection.conf`, else the default. `--archs` or `--features` without `--write` only validates.
- `--src` defaults to `$MAXINE_AR_SRC`, else the `MAXINE_AR_SRC` of the current `selection.conf`, else `~/Downloads/maxine/ar-sdk`. The output says which one it used. A path containing a newline is refused. `assemble.sh --scan` reads the source, so the same layout rules and refusals apply as in the build.
- `--detect-gpu` runs `nvidia-smi --query-gpu=name,compute_cap --format=csv,noheader` and suggests the `sm_` value. Nothing else runs `nvidia-smi`: the query wakes a sleeping discrete GPU.

### selection.conf

`selection.conf` is git-ignored: it holds a path on your machine. It contains comment lines and exactly these keys:

```
MAXINE_AR_SRC=/home/you/Downloads/maxine/ar-sdk
MAXINE_AR_ARCHS=sm_120
MAXINE_AR_FEATURES=all
```

The PKGBUILD reads it in `prepare()` only, so `makepkg --printsrcinfo` does not depend on it. [`selection.sh`](selection.sh) parses it as `KEY=value` lines and never sources or executes it. These stop the build with the line number:

- an unknown key, or a line that is not `KEY=value`;
- a key given twice, or an empty value;
- a value containing `$`, a backtick, a quote or a control character;
- a `MAXINE_AR_SRC` that is not an absolute path.

### GPU architectures

An architecture is the GPU's compute capability without the dot. NVIDIA lists Turing (`sm_75`) and newer GPUs for the AR SDK. Its feature installer fetches 1.2.0.0 Linux models for `sm_75`, `sm_80`, `sm_86`, `sm_89`, `sm_90`, `sm_100` and `sm_120`. The build does not detect the architecture: `nvidia-smi` would wake a sleeping discrete GPU. Look it up once, by hand (or with `./configure.sh --detect-gpu`):

```sh
nvidia-smi --query-gpu=compute_cap --format=csv,noheader   # 12.0 -> sm_120
```

`all` packages every architecture found in the source. In an SDK tree nothing is pruned. From an NGC download, every `<feature>_v1.2.*_models_linux_sm<N>/` directory is used. The summary lists the architectures found.

In an SDK tree, a model file belongs to an architecture when one of the underscore-separated fields of its name is a known SM number: `face_detection_multiprofile_120.engine.trtpkg` is `sm_120`. Files of the other architectures are left out. A file whose name carries no SM number is kept and listed in a note. That includes the files the core itself ships in `lib/models` (the face model `face_model3.nvf` and `face_model3.mtl`, `models.json`, and NVIDIA's custom-model script and its README), which are kept in both layouts. In a download, a file belongs to the architecture of its `models_linux_sm<N>` directory.

Each architecture adds the model packages of every selected feature. In 1.2.0.0 Linux every feature has them. For `sm_120` they are 97,022,776 bytes (92.5 MiB) for eye contact, 50,317,792 bytes (48.0 MiB) for landmark detection, 30,129,624 bytes (28.7 MiB) for face box detection and 1,642,108 bytes (1.6 MiB) for face expressions. Check a package before downloading it with `ngc registry model info nvidia/maxine/<feature>:<version>_models_linux_sm<N>`. The build summary prints the model size per architecture, so the cost is visible.

The build stops in two cases:

- a selected feature that has models in the download lacks them for a selected architecture (the message names the feature, the architecture and the NGC tag);
- a selected architecture has no model files although the source has models for others.

A source without any models only warns, but no AR SDK 1.2.0.0 feature runs without its models.

### Features

The features present in the source are, in an SDK tree, every `features/<feature>/` with `lib/*.so`, and in a download every `nvar*_v1.2.*_lib_linux/*.tar.gz`. With `MAXINE_AR_FEATURES=all` every one of them is packaged. With a list, exactly the listed ones are packaged, and the others are left out (the build summary lists them as "present, not selected"). In a download a feature left out is not unpacked and its models are not copied. In an SDK tree its `features/<feature>/` directory is left out, but its model files cannot be told apart from the others' and stay in `lib/models` (a note says so). At least one feature must be packaged.

To add a feature later, download its library and its models for your architectures into the same directory, run `./configure.sh` again and rebuild the package. Nothing in the PKGBUILD changes.

| Feature | What it does | Needs |
|---|---|---|
| `nvargazeredirection` | eye contact: estimates the gaze and redirects it to the camera | `nvarfaceboxdetection`, `nvarlandmarkdetection` |
| `nvarfaceboxdetection` | face bounding boxes, with tracking for video | |
| `nvarlandmarkdetection` | facial landmarks (68 or 126 points, a performance and a quality mode) and head pose | `nvarfaceboxdetection` |
| `nvarfaceexpressions` | face expression coefficients and head pose | `nvarfaceboxdetection`, `nvarlandmarkdetection` |
| `nvarbodydetection`, `nvarbodyposeestimation`, `nvarlipsync` | body detection, body pose, lip synchronisation | see NVIDIA's documentation |

A feature lists the features it needs in its `<Name>_dependencies.txt`, by library name and separated by semicolons (`nvARFaceBoxDetection;nvARLandmarkDetection;`). The build reads those names as feature names (`nvarfaceboxdetection`). When one of them is not present, or present but not selected, the build prints a warning and goes on.

### One package

The result is one package, `maxine-ar-sdk-local`, holding whatever was downloaded. Split packages per feature were rejected:

- makepkg needs `pkgname=()` and the `package_<name>()` functions fixed when it parses the PKGBUILD (`makepkg --printsrcinfo` and `.SRCINFO` must not depend on the user's download), while the feature set is only known after reading the download.
- A hard-coded per-feature list would produce empty packages for absent features and need a PKGBUILD edit for each new NVIDIA feature.
