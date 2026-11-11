# maxine-ar: the Maxine AR SDK as a local package

[`PKGBUILD`](PKGBUILD) turns your own download of the NVIDIA Maxine AR SDK 1.2.0.0 into a local Arch package, `maxine-ar-sdk-local`, that several projects on the machine can share. Download the SDK yourself, after accepting NVIDIA's licence ([../docs/download.md](../docs/download.md)); this directory holds only the recipe. The built package contains NVIDIA software: keep it on your own machine and never share or upload it.

## What the package installs

| Path | Content |
|---|---|
| `/opt/nvidia/maxine/arsdk/` | the SDK tree (`lib/`, `lib/models/`, `features/`, `include/`, `external/cuda`, `external/tensorrt`, `share/`) |
| `/usr/lib/maxine-ar/os-release-shim.so` | the os-release shim, a compatibility shim for distributions the SDK does not list; NVIDIA does not support this configuration ([../tools/os-release-shim/](../tools/os-release-shim/README.md)) |
| `/usr/lib/maxine-ar/fake-os-release` | the replacement `os-release` (Ubuntu 24.04) |
| `/usr/share/maxine-ar/maxine-ar.env` | the environment file a consumer loads ([../docs/usage.md](../docs/usage.md)) |
| `/usr/share/licenses/maxine-ar-sdk-local/` | links to the SDK's licence files, and this repository's licence (the shim) |
| `/usr/share/doc/maxine-ar-sdk-local/usage.md` | how a project uses the package |

Nothing goes under `/etc`, and nothing sets `LD_LIBRARY_PATH` or `LD_PRELOAD` globally: the bundled CUDA 12.8, cuDNN 9.7 and TensorRT 10.9 would shadow the system's for every program. The selected features are packaged (by default every feature found in the source), with the models of the selected GPU architectures; no engine cache directory is created. The environment file records what went in: `MAXINE_AR_FEATURES` and `MAXINE_AR_ARCHS` (comma-separated, e.g. `nvarfaceboxdetection,nvargazeredirection,nvarlandmarkdetection` and `sm_120`), and one `features/<feature>/lib` entry per feature on the library path.

## Downloading

[`download.sh`](download.sh) fetches the SDK from NGC with your own, configured NGC CLI. It detects your GPU architecture, probes NGC for the sizes, prints a table, asks for confirmation, downloads only what is missing, verifies each item and retries failures:

```sh
./download.sh                     # preset broadcast (eye contact, face box and landmark detection) for your GPU
./download.sh --dry-run           # table and commands only, nothing downloaded
./download.sh --preset all --yes  # all seven documented features, no question
./download.sh --list              # the documented features on NGC, with sizes
./download.sh --yes --build       # download, then configure.sh --write and makepkg -f; never installs
```

The default destination is `~/Downloads/maxine/ar-sdk`, a directory of its own next to a Video Effects SDK download. The script uses the NGC CLI only; it never runs NVIDIA's `features/install_feature.sh`, which installs into `/usr/local/ARSDK` with `sudo`. The `broadcast` preset is eye contact (`nvargazeredirection`) with the two features its `nvARGazeRedirection_dependencies.txt` names. The feature list is the one in the SDK's `features/README.md` and Linux installation guide, which NVIDIA calls non-exhaustive; another name can be given with `--features`.

The options (`--dest`, `--archs`, `--preset`, `--features`, `--version`, `--retries`, `--yes`, `--dry-run`, `--build`, `--list`), the account setup and the manual `ngc` commands are in [../docs/download.md](../docs/download.md).

## Source layouts

`MAXINE_AR_SRC` (default: this directory) may hold either:

1. **An SDK tree**: the directory itself, or its `ARSDK/` subdirectory, contains `lib/libnvARPose.so`, `share/arsdk_version.h`, `features/<feature>/lib/*.so` and `lib/models/*.trtpkg`, for example a previous install under `~/.local/opt/maxine/ARSDK`.
2. **An NGC download**, the directories as `ngc ... download-version` creates them: `ar_sdk_core_v1.2.0.0_linux/ARSDK_linux_1.2.0.0.tgz` (or the bare `.tgz`), `<feature>_v1.2.*_lib_linux/*.tar.gz` for each feature, and `<feature>_v1.2.*_models_linux_sm<N>/` for each feature with models and each architecture. A feature's MAJOR.MINOR must equal the SDK's (1.2). The core resource directory also holds `ARSDK_triton_1.2.0.0.tgz`, the client for NVIDIA's Triton inference server; it is not packaged.

Keep one layout per directory: a source holding both an SDK tree and NGC downloads stops the build, which asks you to move one away or to point `MAXINE_AR_SRC` at the one you mean. Each models directory used must hold the model files directly inside (at least one, no subdirectories), and a file name that appears in two models directories must have the same content in both.

Symbolic links in the source: a link to a directory, or to an existing file outside the tree, stops the build (it would put a link into your home directory in the package, and removing the engine cache through it would delete your own files). Dangling links are kept exactly as NVIDIA ships them and counted in the summary; the 1.2.0.0 core has none (its 80 links all point to files inside the tree).

The source is never modified. [`assemble.sh`](assemble.sh) builds the tree and checks it: the version header, the core libraries, one library per feature, and models for every selected architecture. It ends with a summary: the mode, the version, the features, the architectures packaged, and the number and size of the model files per architecture.

## Build inputs

| Variable | Default | Meaning |
|---|---|---|
| `MAXINE_AR_SRC` | this directory | where the download or tree is |
| `MAXINE_AR_ARCHS` | `sm_120` (`_maxine_archs` in the PKGBUILD) | GPU architectures whose models are packaged: `sm_120`, `sm120` or `120`, space- or comma-separated, e.g. `"sm_120 sm_89"`; or `all`, alone |
| `MAXINE_AR_FEATURES` | `all` | `all`: every feature present is packaged. A list, space- or comma-separated, e.g. `nvargazeredirection,nvarfaceboxdetection,nvarlandmarkdetection`: exactly those are packaged, and the build fails when one of them is missing |

Each value comes from the environment variable of that name when it is set and not empty, else from `selection.conf` in this directory, else from the default. `prepare()` prints every value and where it came from (`environment`, `selection.conf` or `default`).

### Choosing with configure.sh

[`configure.sh`](configure.sh) shows what a download holds and saves the selection in `selection.conf`. It reads the source without network access, never runs `ngc`, NVIDIA's `install_feature.sh` or `sudo`, and extracts nothing:

```sh
./configure.sh --src ~/Downloads/maxine/ar-sdk     # what is present, what the SDK offers, the current selection
./configure.sh --src ~/Downloads/maxine/ar-sdk --archs sm_120 --features all --write
./configure.sh --show                              # print the current selection.conf
./configure.sh --detect-gpu                        # opt-in: asks nvidia-smi for the architecture
```

- Without `--write` it prints the features present in the source with the architectures of their models (in an SDK tree, model files are not tied to a feature, so the architectures are given for the tree as a whole), the features NVIDIA documents for the SDK 1.2, the architectures NVIDIA's feature installer fetches 1.2.0.0 Linux models for, the current selection, and the commands to change it or to fetch more.
- `--write` validates the selection against what is present: a feature or architecture that is not there is an error that names the `ngc` command fetching it. It then replaces `selection.conf` atomically (a temporary file, then a rename) and prints the result. An option left out keeps the value of the current `selection.conf`, else the default. `--archs` or `--features` without `--write` only validates.
- `--src` defaults to `$MAXINE_AR_SRC`, else the `MAXINE_AR_SRC` of the current `selection.conf`, else `~/Downloads/maxine/ar-sdk`; the output says which one it used. A path containing a newline is refused. The source is read by `assemble.sh --scan`, so the same layout rules and refusals apply as in the build.
- `--detect-gpu` runs `nvidia-smi --query-gpu=name,compute_cap --format=csv,noheader` and suggests the `sm_` value. Nothing else runs `nvidia-smi`: the query wakes a sleeping discrete GPU.

### selection.conf

`selection.conf` is git-ignored: it holds a path on your machine. It contains comment lines and exactly these keys:

```
MAXINE_AR_SRC=/home/you/Downloads/maxine/ar-sdk
MAXINE_AR_ARCHS=sm_120
MAXINE_AR_FEATURES=all
```

The PKGBUILD reads it in `prepare()` only, so `makepkg --printsrcinfo` does not depend on it. It is parsed by [`selection.sh`](selection.sh) as `KEY=value` lines and never sourced or executed. An unknown key, a line that is not `KEY=value`, a key given twice, an empty value, a value containing `$`, a backtick, a quote or a control character, and a `MAXINE_AR_SRC` that is not an absolute path stop the build with the line number.

### GPU architectures

An architecture is the GPU's compute capability without the dot. NVIDIA lists Turing (`sm_75`) and newer GPUs for the AR SDK; its feature installer fetches 1.2.0.0 Linux models for `sm_75`, `sm_80`, `sm_86`, `sm_89`, `sm_90`, `sm_100` and `sm_120`. The build does not detect the architecture: `nvidia-smi` would wake a sleeping discrete GPU. Look it up once, by hand (or with `./configure.sh --detect-gpu`):

```sh
nvidia-smi --query-gpu=compute_cap --format=csv,noheader   # 12.0 -> sm_120
```

`all` packages every architecture found in the source: in an SDK tree nothing is pruned, and from an NGC download every `<feature>_v1.2.*_models_linux_sm<N>/` directory is used. The summary lists the architectures found.

In an SDK tree, a model file belongs to an architecture when one of the underscore-separated fields of its name is a known SM number: `face_detection_multiprofile_120.engine.trtpkg` is `sm_120`. Files of the other architectures are left out; a file whose name carries no SM number is kept and listed in a note. That includes the files the core itself ships in `lib/models` (the face model `face_model3.nvf` and `face_model3.mtl`, `models.json`, and NVIDIA's custom-model script and its README), which are kept in both layouts. In a download, a file belongs to the architecture of its `models_linux_sm<N>` directory.

Each architecture adds the model packages of every selected feature. In 1.2.0.0 Linux every feature has them; for `sm_120` they are 97,022,776 bytes (92.5 MiB) for eye contact, 50,317,792 bytes (48.0 MiB) for landmark detection, 30,129,624 bytes (28.7 MiB) for face box detection and 1,642,108 bytes (1.6 MiB) for face expressions. Check a package before downloading it with `ngc registry model info nvidia/maxine/<feature>:<version>_models_linux_sm<N>`. The build summary prints the model size per architecture, so the cost is visible.

The build stops when a selected feature that has models in the download lacks them for a selected architecture (the message names the feature, the architecture and the NGC tag), and when a selected architecture has no model files although the source has models for others. A source without any models only warns, but no AR SDK 1.2.0.0 feature runs without its models.

### Features

The features present in the source are, in an SDK tree, every `features/<feature>/` with `lib/*.so`, and in a download every `nvar*_v1.2.*_lib_linux/*.tar.gz`. With `MAXINE_AR_FEATURES=all` every one of them is packaged; with a list, exactly the listed ones, and the others are left out (the build summary lists them as "present, not selected"). In a download a feature left out is not unpacked and its models are not copied. In an SDK tree its `features/<feature>/` directory is left out, but its model files cannot be told apart from the others' and stay in `lib/models` (a note says so). At least one feature must be packaged. To add a feature later, download its library and its models for your architectures into the same directory, run `./configure.sh` again and rebuild the package; nothing in the PKGBUILD changes.

| Feature | What it does | Needs |
|---|---|---|
| `nvargazeredirection` | eye contact: estimates the gaze and redirects it to the camera | `nvarfaceboxdetection`, `nvarlandmarkdetection` |
| `nvarfaceboxdetection` | face bounding boxes, with tracking for video | |
| `nvarlandmarkdetection` | facial landmarks (68 or 126 points, a performance and a quality mode) and head pose | `nvarfaceboxdetection` |
| `nvarfaceexpressions` | face expression coefficients and head pose | `nvarfaceboxdetection`, `nvarlandmarkdetection` |
| `nvarbodydetection`, `nvarbodyposeestimation`, `nvarlipsync` | body detection, body pose, lip synchronisation | see NVIDIA's documentation |

A feature lists the features it needs in its `<Name>_dependencies.txt`, by library name and separated by semicolons (`nvARFaceBoxDetection;nvARLandmarkDetection;`); the build reads those names as feature names (`nvarfaceboxdetection`). When one of them is not present, or present but not selected, the build prints a warning and goes on.

### One package

The result is one package, `maxine-ar-sdk-local`, holding whatever was downloaded. Split packages per feature were rejected: makepkg needs `pkgname=()` and the `package_<name>()` functions fixed when it parses the PKGBUILD (`makepkg --printsrcinfo` and `.SRCINFO` must not depend on the user's download), while the feature set is only known after reading the download. A hard-coded per-feature list would produce empty packages for absent features and need a PKGBUILD edit for each new NVIDIA feature.

## Build and install

From this directory:

```sh
./configure.sh --src ~/Downloads/maxine/ar-sdk --archs sm_120 --features all --write
makepkg -f
# or without selection.conf, from an existing SDK tree:
MAXINE_AR_SRC=~/.local/opt/maxine/ARSDK makepkg -f
# from an NGC download, for two architectures:
MAXINE_AR_SRC=~/Downloads/maxine/ar-sdk MAXINE_AR_ARCHS="sm_120 sm_89" makepkg -f
# exactly the features a consumer needs (the build fails when one is missing):
MAXINE_AR_SRC=~/Downloads/maxine/ar-sdk MAXINE_AR_FEATURES=nvargazeredirection,nvarfaceboxdetection,nvarlandmarkdetection makepkg -f
```

With the four features eye contact, face box detection, landmark detection and face expressions, and `sm_120` models, the SDK tree is 4,757,681,936 bytes (4.43 GiB), of which 183,014,313 bytes (175 MiB) are `lib/models`; most of the rest is the bundled CUDA and TensorRT libraries, which every selection carries. The uncompressed package is 4,758,773,760 bytes; `PKGEXT=.pkg.tar` in front of `makepkg` skips a slow compression. Then install it yourself:

```sh
sudo pacman -U maxine-ar-sdk-local-*-x86_64.pkg.tar*
```

Disk space: the build copies the tree into `src/` and `pkg/` and writes the package file; on btrfs (or another filesystem with reflinks) the copies share their data, otherwise plan for about three times the tree's size, plus the installed tree. `makepkg -c` removes `src/` and `pkg/` after the build.

The probe in [../tools/maxine-probe/](../tools/maxine-probe/README.md) checks the Video Effects SDK; it does not exercise this package.

## Uninstall

```sh
sudo pacman -R maxine-ar-sdk-local
```
