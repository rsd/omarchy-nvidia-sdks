# Downloading the Maxine Video Effects SDK

The `maxine-vfx-sdk-local` package is built from files you download yourself from NVIDIA NGC after accepting NVIDIA's licence. This repository does not contain, and cannot provide, any of those files. This page is a step-by-step guide for SDK 1.3.0.0 (Linux).

There are two ways to download:

- **Automated:** [`maxine-vfx/download.sh`](../maxine-vfx/download.sh) detects your GPU, shows what it would download and how big it is, asks for confirmation, and fetches only what is missing. See [Download with one command](#download-with-one-command).
- **Manual:** the same `ngc` commands, written out. See [Download by hand](#download-by-hand).

Both need the prerequisites below and both use your own, configured NGC CLI. Read the licence terms shown at the NGC pages before you accept them. See the "Licence and personal use" section of the [README](../README.md).

## Prerequisites

| Item | Requirement | Check |
|---|---|---|
| GPU | NVIDIA, compute capability 7.5 or newer (Turing and later) | `nvidia-smi --query-gpu=name,compute_cap --format=csv` |
| Driver | 570.26 or newer | `nvidia-smi --query-gpu=driver_version --format=csv,noheader` |
| System CUDA toolkit | Not needed. The SDK bundles CUDA 12.8, cuDNN 9 and TensorRT 10 and takes only `libcuda.so.1` from the driver (`nvidia-utils`) | |
| Tools | `curl`, `unzip`, `jq` (to install the NGC CLI) | `pacman -S --needed curl unzip jq` |
| Disk | The default download (SDK core, three feature libraries, two model sets, one architecture) is about 2.75 GiB. The extracted SDK tree is 4.4 GiB (4,671,229,191 bytes), the built package (`PKGEXT=.pkg.tar`) is about 4.4 GiB too. With all eight features and `sm_120` models the tree is 5,054,183,158 bytes (4.71 GiB) and the package about 4.7 GiB. `makepkg` needs space for its working copy as well. More features and architectures add to this: see [Sizes](#sizes) | `df -h ~` |

### 1. NVIDIA account and access (manual)

A plain NGC account is not enough. A free NVIDIA Developer Program membership gives Maxine access; NVIDIA AI Enterprise is not required.

1. Create or log in to an NVIDIA Developer Program account. Use this one account for NGC, the Developer Program and the API key in step 2.
2. Open <https://catalog.ngc.nvidia.com/orgs/nvidia/maxine/resources/vfx_sdk_core> ("NVIDIA Video Effects SDK Core") and log in.
3. Under "NVIDIA Developer Program", select **Get Access** and accept the terms.

The API key in step 2 must come from the account and organisation that hold this access. Otherwise downloads fail with an access error (see [Troubleshooting](#troubleshooting)).

### 2. Personal API key (manual)

1. Open <https://org.ngc.nvidia.com/setup/personal-keys> and select **Generate Personal Key**.
2. Include the **NGC Catalog** service. Choose an expiry you are comfortable with.
3. Copy the key (`nvapi-...`) immediately; it is shown once. Keep it out of any repository and out of your shell history. You enter it in `ngc config set` in step 4.

### 3. Install the NGC CLI

Arch has no package for the NGC CLI. Install the official zip into your user prefix. Pin the version in `NGC_VER`; 4.36.6 was current when this page was written, and the newest version is the first entry of the version list.

```bash
# newest published version
curl -s https://api.ngc.nvidia.com/v2/resources/nvidia/ngc-apps/ngc_cli/versions | jq -r '.recipeVersions[0].versionId'

NGC_VER=4.36.6
D=$(mktemp -d) && cd "$D"
curl -L -o ngccli_linux.zip \
  "https://api.ngc.nvidia.com/v2/resources/nvidia/ngc-apps/ngc_cli/versions/$NGC_VER/files/ngccli_linux.zip"
unzip -q ngccli_linux.zip                      # creates ngc-cli/ and ngc-cli.md5

# integrity check: the two hashes must be identical
find ngc-cli/ -type f -exec md5sum {} + | LC_ALL=C sort | md5sum
cat ngc-cli.md5

mkdir -p ~/.local/opt ~/.local/bin
mv ngc-cli ~/.local/opt/ngc-cli
ln -sf ~/.local/opt/ngc-cli/ngc ~/.local/bin/ngc
cd ~ && rm -rf "$D"
ngc --version
```

`~/.local/bin` must be on `PATH`.

### 4. Configure the NGC CLI (manual)

```bash
ngc config set
```

Run this yourself and answer the prompts interactively. The key is entered here and nowhere else: it never goes into a script, a log or your shell history.

- API key: paste the `nvapi-...` key from step 2.
- CLI output format: `ascii`.
- org: the organisation of the account that has the Developer Program access. The prompt lists the organisations your key can see.
- team and ace: press Enter to accept the defaults.

The NGC CLI stores the key in `~/.ngc/config`. Nothing in this repository reads that file, and the scripts never ask for, pass on or print the key.

Check access (read-only):

```bash
ngc registry resource info nvidia/maxine/vfx_sdk_core:1.3.0.0_linux
```

This prints the details of the SDK core. If it fails, see [Troubleshooting](#troubleshooting).

## Download with one command

From the root of this repository:

```bash
maxine-vfx/download.sh
```

With no options the script:

1. detects your GPU architecture with `nvidia-smi`;
2. selects the `broadcast` preset: AI green screen, background blur and video noise removal, plus the SDK core;
3. asks NGC for the size of every item (read-only) and prints a table: item, size, number of files and status (present, missing, incomplete, no model package, unavailable, or probe failed when NGC gave another error such as a timeout or a 5xx: that item is not downloaded and the run fails);
4. asks `Download N items (X GiB) into DIR? [y/N]`;
5. downloads only the items that are missing or incomplete, into `~/Downloads/maxine`, checks each against the size and file count NGC reported, and retries a failed item;
6. prints the commands for the next steps.

An item that is already complete is skipped, so running the script again is safe. Authentication is the NGC CLI's business: the script never reads `~/.ngc` and never handles the key.

Options:

| Option | Meaning |
|---|---|
| `--dry-run` | Probe NGC and print the table, then print the exact `ngc` download commands and stop. Nothing is downloaded or created, and it never asks |
| `--dest DIR` | Download directory. Default `~/Downloads/maxine` |
| `--archs LIST` | GPU architectures: `auto` (default, from `nvidia-smi`), `all`, or a list such as `sm_120,sm_89` (`sm_120`, `sm120` and `120` are the same) |
| `--preset NAME` | `broadcast` (default) or `all`. See [Features](#features) |
| `--features LIST` | An explicit list of NGC feature names instead of a preset, for example `nvvfxgreenscreen,nvvfxrelighting`. Do not combine it with `--preset` |
| `--version V` | SDK version. Default `1.3.0.0` |
| `--retries N` | Extra attempts for an item that fails or does not verify. Default 2 |
| `--yes` | Do not ask for confirmation. Without a terminal, `--yes` is required |
| `--build` | After a fully successful download, run `configure.sh --write` and `makepkg -f` for you. It never installs and never runs `sudo` |
| `--list` | Show which features NGC offers for the chosen architectures, with sizes, and exit. With `--dry-run`, it only prints the read-only `ngc ... info` commands it would run. See [Listing the features](#listing-the-features) |

Examples:

```bash
maxine-vfx/download.sh --dry-run                       # see the table and the commands, change nothing
maxine-vfx/download.sh --yes                           # no confirmation prompt
maxine-vfx/download.sh --preset all                    # every feature below, for your GPU
maxine-vfx/download.sh --features nvvfxgreenscreen,nvvfxrelighting
maxine-vfx/download.sh --archs sm_120,sm_89            # models for two architectures
maxine-vfx/download.sh --archs all                     # models for every architecture
maxine-vfx/download.sh --yes --build                   # download, then configure and build the package
maxine-vfx/download.sh --list                          # what NGC offers
```

If `nvidia-smi` is missing or fails, the script stops and asks you to pass `--archs sm_120` (or your architecture). If an architecture has no model package for a feature, the table shows "no model package" for it. That is reported, not an error.

When the download is complete, the script prints the next steps with your paths filled in. They look like this:

```bash
maxine-vfx/configure.sh --src ~/Downloads/maxine --archs "sm_120" --features nvvfxgreenscreen,nvvfxbackgroundblur,nvvfxdenoising --write
cd maxine-vfx && makepkg -f
sudo pacman -U maxine-vfx-sdk-local-*.pkg.tar*
```

The script only prints the last line. You run `sudo pacman -U` yourself. See [Next step](#next-step).

### Listing the features

NGC hides the Maxine items from `ngc registry model list "nvidia/maxine/nvvfx*"`: every item has the access type `NOT_LISTED`, so that wildcard prints an empty table. `download.sh --list` instead asks about each known feature by name with `ngc registry model info` and prints its function, the closest NVIDIA Broadcast name, the size of its library and the size of its models for each chosen architecture:

```bash
maxine-vfx/download.sh --list                  # your GPU
maxine-vfx/download.sh --list --archs all      # every architecture
```

## Download by hand

These commands do the same downloads as the script (the script stages each item in `DEST/.partial`, checks it and only then moves it into place). This example downloads the default set for an RTX 50 series GPU (`sm_120`) into `~/Downloads/maxine`.

First the SDK core. It is an NGC resource, and the tag ends in `_linux` (`_woa` is Windows on ARM and is not usable):

```bash
ngc registry resource download-version nvidia/maxine/vfx_sdk_core:1.3.0.0_linux --dest ~/Downloads/maxine
```

Then, for each feature, its library, and its models for your architecture if it has any:

```bash
# AI green screen: library and models
ngc registry model download-version nvidia/maxine/nvvfxgreenscreen:1.3.0.0_lib_linux --dest ~/Downloads/maxine
ngc registry model download-version nvidia/maxine/nvvfxgreenscreen:1.3.0.0_models_linux_sm120 --dest ~/Downloads/maxine

# Background blur: library only (it has no models)
ngc registry model download-version nvidia/maxine/nvvfxbackgroundblur:1.3.0.0_lib_linux --dest ~/Downloads/maxine

# Video noise removal: library and models
ngc registry model download-version nvidia/maxine/nvvfxdenoising:1.3.0.0_lib_linux --dest ~/Downloads/maxine
ngc registry model download-version nvidia/maxine/nvvfxdenoising:1.3.0.0_models_linux_sm120 --dest ~/Downloads/maxine
```

For another GPU, replace `sm120` in the `models_linux_sm120` tags with your architecture. The values and how to find yours are in [gpu-support.md](gpu-support.md). To check what a package holds and how big it is before you download it, ask NGC (read-only):

```bash
ngc registry model info nvidia/maxine/nvvfxdenoising:1.3.0.0_models_linux_sm120
```

For any other feature in the [Features](#features) table, use the same two tags with its NGC name, for example `nvvfxrelighting:1.3.0.0_lib_linux` and `nvvfxrelighting:1.3.0.0_models_linux_sm120`. The feature's major and minor version must equal the SDK's (1.3). Ignore NGC entries named `windows_*` and `woa_*`.

If a models tag does not exist for a feature, that feature has no model package for that architecture. Keep the library only.

### Resulting directory

The NGC CLI creates one subdirectory per download. The commands above give:

```
~/Downloads/maxine/
  vfx_sdk_core_v1.3.0.0_linux/                      3 files: VFXSDK_linux_1.3.0.0.tgz, VFXSDK_triton_1.3.0.0.tgz, README_VFX_SDK_Triton.md
  nvvfxgreenscreen_v1.3.0.0_lib_linux/              1 file, a .tar.gz
  nvvfxgreenscreen_v1.3.0.0_models_linux_sm120/     8 .engine.trtpkg files
  nvvfxbackgroundblur_v1.3.0.0_lib_linux/           1 file, a .tar.gz
  nvvfxdenoising_v1.3.0.0_lib_linux/                1 file, a .tar.gz
  nvvfxdenoising_v1.3.0.0_models_linux_sm120/       2 files
```

This is exactly the layout `maxine-vfx/assemble.sh` reads. The package needs only `VFXSDK_linux_1.3.0.0.tgz` from the core; the Triton variant and the README are not used. `download.sh` produces the same directories. While it runs it also uses a temporary `.partial/` directory inside the destination, which it removes when it is empty.

## Sizes

NGC prints sizes with the label "MB" that are really MiB (2^20 bytes). This page and the script use MiB and GiB, stated explicitly. The sizes below are for `sm_120`, as reported by NGC for SDK 1.3.0.0 Linux.

| Item | Size | Files |
|---|---|---|
| SDK core (`vfx_sdk_core`, always fetched) | 2.63 GiB (2,691 MiB) | 3 |
| `nvvfxgreenscreen` library | 2.57 MiB | 1 |
| `nvvfxgreenscreen` models, `sm_120` | 113.14 MiB | 8 |
| `nvvfxbackgroundblur` library | 0.37 MiB | 1 |
| `nvvfxdenoising` library | 2.19 MiB | 1 |
| `nvvfxdenoising` models, `sm_120` | 3.72 MiB | 2 |
| `nvvfxrelighting` library | 2.45 MiB | 1 |
| `nvvfxrelighting` models, `sm_120` | 79.46 MiB | 2 |
| `nvvfxvideosuperres` library | 46.83 MiB | 1 |
| `nvvfxupscale` library | 1.53 MiB | 1 |
| `nvvfxtruehdr` library | 2.22 MiB | 1 |
| `nvvfxvideoframegeneration` library | 179.28 MiB | 1 |

Totals for `sm_120`:

| Preset | Contents | Total |
|---|---|---|
| `broadcast` (default) | core, green screen, background blur, denoising | 2,949,781,243 bytes, about 2.75 GiB |
| `all` | `broadcast` plus relighting, video super resolution, upscale, TrueHDR and video frame generation | 3,276,703,656 bytes, about 3.05 GiB |

For `sm_120`, the five features that `all` adds add 326,922,413 bytes (about 312 MiB) to the download: relighting library 2.4 MiB plus `sm_120` models 79.5 MiB, video super resolution 46.8 MiB, upscale 1.5 MiB, TrueHDR 2.2 MiB and video frame generation 179.3 MiB. Only relighting has models. The assembled SDK tree with all eight features and `sm_120` models is 5,054,183,158 bytes (4.71 GiB).

All eight features were checked to create and load their effect on an `sm_120` GPU with driver 615.78. This was a load check, not a benchmark.

The SDK core is by far the largest item. Each extra GPU architecture adds the model packages of every feature that has models. The per-architecture sizes are in [gpu-support.md](gpu-support.md#size-cost-per-architecture). The build prints the model size per architecture at the end, so the cost of the finished package is visible. Package only the architectures of the machines you build for.

## Features

SDK 1.3.0.0 for Linux offers eight features on NGC. The `broadcast` preset is the set a webcam pipeline needs; `all` is the eight. The mapping to NVIDIA Broadcast names is by function: NVIDIA does not document it, so treat it as a guide.

| NGC name | What it does | Closest NVIDIA Broadcast or RTX name | Preset |
|---|---|---|---|
| `nvvfxgreenscreen` | AI green screen: a person and background mask, used for background removal and replacement | Background Removal, Background Replacement | `broadcast`, `all` |
| `nvvfxbackgroundblur` | Blurs the background using a mask (pairs with green screen) | Background Blur | `broadcast`, `all` |
| `nvvfxdenoising` | Video noise removal: webcam sensor noise in low light | Video Noise Removal | `broadcast`, `all` |
| `nvvfxrelighting` | Video relighting: relights the subject | Virtual Key Light (closest match) | `all` |
| `nvvfxvideosuperres` | Video Super Resolution: upscales and enhances video | RTX Video Super Resolution (closest match; a driver feature, not part of Broadcast) | `all` |
| `nvvfxupscale` | Fast upscaling with sharpening | none | `all` |
| `nvvfxtruehdr` | SDR to HDR conversion | RTX Video HDR (closest match; a driver feature) | `all` |
| `nvvfxvideoframegeneration` | Video frame generation: interpolates frames | none | `all` |

Notes:

- Model packages exist only for green screen, denoising and relighting. The other five features are a library only.
- **Eye Contact and Auto Frame** in NVIDIA Broadcast belong to the Maxine AR SDK, not to this Video Effects SDK. They are not downloaded or packaged here.
- Artifact reduction (`nvvfxartifactreduction`) is not on NGC for 1.3.0.0; the 1.1.0.0 Changelog says it was removed. Two more names, `nvvfxvfg` and `nvvfxframegeneration`, are not available either. NGC answers 403 for them.
- Some features ship a `<Name>_dependencies.txt`. If one names other features that are not in your download, the build prints a warning listing them. Download those features as well.

### More features

The package contains the features you select from your download directory. To add one later, download its library and models into the same directory (`download.sh --features ...` or the manual commands above), run `maxine-vfx/configure.sh` again and rebuild. Nothing in the recipe changes: a feature the package has never seen needs no edit to the PKGBUILD.

## Next step

Look at what your download holds and choose what to package. This reads the directory only, without network access and without running `ngc`:

```bash
maxine-vfx/configure.sh --src ~/Downloads/maxine                                   # present, offered, current selection
maxine-vfx/configure.sh --src ~/Downloads/maxine --archs sm_120 --features all --write
```

The second command validates the selection against what is present and writes `maxine-vfx/selection.conf`, which the PKGBUILD reads when it builds. The file is git-ignored because it holds a local path. The PKGBUILD takes each value from the environment variable of that name, else from `selection.conf`, else from its default (the source: the PKGBUILD directory; `sm_120`; `all`). Put nothing but `KEY=value` lines in it: it is parsed, not executed.

Then build:

```bash
cd maxine-vfx && makepkg -f
```

or, without `selection.conf`, with the environment variables:

```bash
cd maxine-vfx && MAXINE_VFX_SRC=~/Downloads/maxine MAXINE_VFX_ARCHS=sm_120 MAXINE_VFX_FEATURES=all makepkg -f
```

- `MAXINE_VFX_ARCHS` selects the architectures (`sm_120`, `sm120` or `120`; a comma or space separated list; or `all`, alone). See [gpu-support.md](gpu-support.md).
- `MAXINE_VFX_FEATURES` is `all` (the default: every feature found in the download is packaged) or a comma or space separated list. A listed feature must be present, otherwise the build fails and names the missing feature and the `ngc` command that fetches it. A feature that is present but not listed is left out, and the build summary says "present, not selected". A program that needs only green screen and background blur, for example, can build with:

  ```bash
  MAXINE_VFX_FEATURES=nvvfxgreenscreen,nvvfxbackgroundblur
  ```

Install the result yourself with `sudo pacman -U`, then continue with [usage.md](usage.md).

## Alternative: an existing SDK tree

If you already have an assembled SDK tree, for example a previous user-prefix install such as `~/.local/opt/maxine/VideoFX`, you do not need the downloads. Point `MAXINE_VFX_SRC` at the tree (or at its parent directory):

```bash
cd maxine-vfx && MAXINE_VFX_SRC=~/.local/opt/maxine/VideoFX makepkg -f
```

The tree must contain `lib/libVideoFX.so`, `share/videofx_version.h` and `features/<feature>/lib/*.so`, and normally `lib/models/*.trtpkg`.

## Troubleshooting

### `ngc registry model list "nvidia/maxine/nvvfx*"` prints an empty table

This is expected. NGC marks every Maxine item `NOT_LISTED`, so wildcard model listing hides them. The items exist and can be downloaded. To discover them, use one of:

```bash
maxine-vfx/download.sh --list                                       # all known features, with sizes
ngc registry model info nvidia/maxine/nvvfxgreenscreen:1.3.0.0_lib_linux     # one item by name
ngc registry model list "nvidia/maxine/nvvfxgreenscreen:*"          # the versions of one feature
```

### Authentication, configuration or access errors

- **`Target 'nvidia/maxine/...' could not be found`**, or `download.sh` saying that the NGC CLI cannot see the SDK core. An NGC CLI that is not configured gives this message instead of "unauthorised". Run `ngc config set` yourself (step 4). The same message can mean an invalid or expired key, or that the machine is offline. The SDK core always exists, so a failure on it points at your setup and not at the item.
- **`403 Response: Access Denied`** for an item. The item does not exist, or your account has no access to it. Check:
  - that you accepted the terms under **Get Access** in step 1, with the account that owns the key;
  - that the key includes the **NGC Catalog** service and has not expired (step 2);
  - that `ngc config set` has the organisation that holds the access (step 4);
  - that the name is right (`download.sh --list` shows the known names). Artifact reduction, for example, is not on NGC for 1.3.0.0.
- **Only `_woa` or `windows` entries, or an SDK with no Linux libraries.** Wrong tag: `_woa` is Windows on ARM. Use the `_linux` tags shown above.

### The architecture is wrong or has no models

`download.sh` takes the architecture from `nvidia-smi --query-gpu=compute_cap --format=csv,noheader`. The value `12.0` becomes `sm_120`, `8.6` becomes `sm_86` and `10.0` becomes `sm_100`: remove the dot. A GPU below 7.5 is not supported, and the script stops.

- To use another architecture than the one detected, pass it: `download.sh --archs sm_89`. This is also needed when `nvidia-smi` is not available.
- If the table says "no model package" for a feature, NGC has no models for that feature and architecture. In 1.3.0.0, background blur, video super resolution, upscale, TrueHDR and video frame generation have no model package. For green screen, denoising and relighting, check that your architecture is in the [table of architectures](gpu-support.md#architectures-with-models-in-1300-linux). A value that is not in the table, such as 8.7 or 12.1, has no exact model package.
- The build stops with a missing models directory for a feature, architecture and NGC tag when a selected architecture has no models for a feature that has models in your download. Download the tag named in the message, or leave that architecture out of `MAXINE_VFX_ARCHS` (`configure.sh` shows what is present).

### The download was interrupted

Run the same `download.sh` command again. Items that are complete (the file count and size match what NGC reports) are skipped, and incomplete ones are downloaded again. A failed item is also retried automatically, `--retries` times. The `.partial/` directory in the destination is the script's staging area; it is safe to delete when the script is not running.

For a manual download, delete the incomplete directory and run the command again.

### `ngc` is not on PATH

`download.sh` stops and says so. Complete [step 3](#3-install-the-ngc-cli). The CLI is linked into `~/.local/bin`, which must be on your `PATH`; check with `command -v ngc`.

### Other

| Symptom | Cause | Fix |
|---|---|---|
| `download.sh` says to pass `--yes` | There is no terminal to ask the confirmation on | Add `--yes`, or run it from a terminal |
| `download.sh` says to pass `--archs` | `nvidia-smi` is missing or failed | Pass your architecture, for example `--archs sm_120` |
| `download.sh` reports a feature as "unavailable (unknown name or no access)" | The feature name is not on NGC for this version, or you have no access to it | Check the name with `download.sh --list` |
| `download.sh` reports an item as "probe failed: ..." | NGC answered the `info` request with an error other than 403 or "could not be found", such as a timeout, a server error or a rate limit | Run the script again later. The item is not downloaded, the run fails and `--build` does not run |
| A feature has no models in the table | It has no model package for that architecture | Nothing to fix. See above |
