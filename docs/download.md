# Downloading the Maxine Video Effects SDK

The `maxine-vfx-sdk-local` package is built from files you download yourself from NVIDIA NGC after accepting NVIDIA's licence. This repository does not contain, and cannot provide, any of those files. This page lists the exact steps for SDK 1.3.0.0 (Linux), for any feature and any GPU architecture NVIDIA publishes for it, not only the defaults.

Steps marked **Manual** need your NVIDIA credentials and cannot be scripted. The scripted equivalent of steps 4 and 5 is [`maxine-vfx/download.sh`](../maxine-vfx/download.sh).

Read the licence terms shown at the download pages before you accept them. See the "Licence and personal use" section of the [README](../README.md).

## Prerequisites

| Item | Requirement | Check |
|---|---|---|
| GPU | NVIDIA, compute capability 7.5 or newer (Turing and later) | `nvidia-smi --query-gpu=name,compute_cap --format=csv` |
| Driver | 570.26 or newer | `nvidia-smi --query-gpu=driver_version --format=csv,noheader` |
| System CUDA toolkit | Not needed. The SDK bundles CUDA 12.8, cuDNN 9 and TensorRT 10 and takes only `libcuda.so.1` from the driver (`nvidia-utils`) | |
| Tools | `curl`, `unzip`, `jq` | `pacman -S --needed curl unzip jq` |
| Disk | The default downloads (core, two feature libraries, one architecture) are about 2.7 GiB; the extracted SDK tree is 4.4 GiB (4,671,229,191 bytes), the built package (`PKGEXT=.pkg.tar`) is about 4.4 GiB too, and `makepkg` needs space for its working copy as well. More features and more architectures add to this: see [Size cost](#size-cost-per-architecture) | `df -h ~` |

## 1. NVIDIA account and access (Manual)

A plain NGC account is not enough. A free NVIDIA Developer Program membership is enough; NVIDIA AI Enterprise is not required.

1. Create or log in to an NVIDIA Developer Program account. Use this one account for NGC, the Developer Program and the API key in step 2.
2. Open <https://catalog.ngc.nvidia.com/orgs/nvidia/maxine/resources/vfx_sdk_core> ("NVIDIA Video Effects SDK Core") and log in.
3. Under "NVIDIA Developer Program", select **Get Access** and accept the terms.

The API key in step 2 must come from the account and organisation that hold this access. Otherwise downloads fail with 403 or 402.

## 2. Personal API key (Manual)

1. Open <https://org.ngc.nvidia.com/setup/personal-keys> and select **Generate Personal Key**.
2. Include the **NGC Catalog** service. Choose an expiry you are comfortable with.
3. Copy the key (`nvapi-...`) immediately; it is shown once. Keep it out of any repository and out of your shell history. You paste it into `ngc config set` in step 3.

## 3. NGC CLI

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

### Configure (Manual)

```bash
ngc config set
```

Answer the prompts interactively, so that the key never ends up in a script, a log or your shell history:

- API key: paste the `nvapi-...` key from step 2.
- CLI output format: `ascii`.
- org: the organisation of the account that has the Developer Program access. The prompt lists the organisations your key can see.
- team and ace: press Enter to accept the defaults.

The NGC CLI stores the key in `~/.ngc/config`. Nothing in this repository reads that file.

Check access (read-only):

```bash
ngc registry resource list "nvidia/maxine/vfx_sdk_core:*"
```

A table of versions should appear (`1.3.0.0_linux`, `1.3.0.0_woa`, and others). An authorisation error means the key or the organisation is wrong; see the table at the end of this page.

## 4. Download the core SDK

Tags carry a platform suffix. Use `_linux`. `_woa` is Windows on ARM and is not usable.

Pick one download directory. It becomes `MAXINE_VFX_SRC` when you build the package. The examples use `~/Downloads/maxine`:

```bash
DIR=~/Downloads/maxine
mkdir -p "$DIR"
ngc registry resource download-version "nvidia/maxine/vfx_sdk_core:1.3.0.0_linux" --dest "$DIR"
```

The core download holds `VFXSDK_linux_1.3.0.0.tgz` (the one the package needs), a Triton client variant and a short README. The last two are not needed. The tarball is 2,815,877,830 bytes, which is 2.62 GiB or 2.82 GB. NGC lists the whole resource as "2.63 GB"; that figure is in GiB (2^30 bytes), not GB (10^9 bytes). This page states GiB or GB explicitly.

## 5. Download the features and the GPU-architecture models

Each feature has a library package (`<feature>:1.3.0.0_lib_linux`) and, for most features, one model package per GPU architecture (`<feature>:1.3.0.0_models_linux_sm<N>`). The models are TensorRT engines built for one architecture. Background blur is CUDA compositing on top of an external mask and has no model package.

Find your architecture once, by hand. The package build never probes the GPU (it would wake a discrete GPU for nothing), so you look the value up once and pass it explicitly:

```bash
nvidia-smi --query-gpu=compute_cap --format=csv,noheader   # 12.0 means sm_120, 8.9 means sm_89
SM=120                                                     # the number without the dot
```

Discover which features NGC offers (read-only, nothing is downloaded):

```bash
ngc registry model list "nvidia/maxine/nvvfx*"
ngc registry model list "nvidia/maxine/nvvfxgreenscreen:*"     # the tags of one feature
```

The architectures that have 1.3.0.0 Linux models, with example GPUs and the tag and directory names, are in the table in [gpu-support.md](gpu-support.md#architectures-with-models-in-1300-linux). Ignore NGC entries named `windows_*` and `woa_*`. If your value is not in the table (for example 8.7 or 12.1), choosing the closest entry is an untested combination that the loader may refuse. The SDK needs a Tensor-core GPU, Turing or newer; see [gpu-support.md](gpu-support.md).

Download the default two features and the models of your architecture:

```bash
ngc registry model download-version "nvidia/maxine/nvvfxgreenscreen:1.3.0.0_lib_linux" --dest "$DIR"
ngc registry model download-version "nvidia/maxine/nvvfxbackgroundblur:1.3.0.0_lib_linux" --dest "$DIR"
ngc registry model download-version "nvidia/maxine/nvvfxgreenscreen:1.3.0.0_models_linux_sm$SM" --dest "$DIR"
```

Sizes: green screen library 2.6 MB, background blur library 0.4 MB, `sm120` green screen models 113 MB (8 `.engine.trtpkg` files). The feature version's major and minor number must equal the SDK's (1.3).

### More features

The package contains every feature it finds in `$DIR`, so adding a feature means downloading it into the same directory and building again. For a feature `<f>`:

```bash
ngc registry model info "nvidia/maxine/<f>:1.3.0.0_lib_linux"                       # check the size first
ngc registry model download-version "nvidia/maxine/<f>:1.3.0.0_lib_linux" --dest "$DIR"
ngc registry model info "nvidia/maxine/<f>:1.3.0.0_models_linux_sm$SM"
ngc registry model download-version "nvidia/maxine/<f>:1.3.0.0_models_linux_sm$SM" --dest "$DIR"
```

If the `models` tag does not exist for a feature, that feature has no model package; keep the library only. Then run `maxine-vfx/configure.sh` and rebuild as described under [Next step](#next-step). Nothing in the recipe changes: a feature the package has never seen needs no edit to the PKGBUILD.

The NGC list is the authoritative source for the names. What this repository knows:

| Feature | NGC name | Notes |
|---|---|---|
| AI green screen | `nvvfxgreenscreen` | has models |
| Background blur | `nvvfxbackgroundblur` | no models |
| Video Super Resolution (VSR) | `nvvfxvideosuperres` | named in the SDK's own `install_feature.sh` |
| Webcam denoising | `nvvfxdenoising` | named in `install_feature.sh` |
| Upscale | `nvvfxupscale` | named in `install_feature.sh` |
| Video Relighting, TrueHDR, Video Frame Generation (VFG) | read the names from the list | named in the 1.3.0.0 Changelog; the NGC names are not assumed here |

Artifact Reduction was removed from the SDK in 1.1.0.0 and is only still named in an `install_feature.sh` example. Eye contact is not part of the Video Effects SDK; it belongs to the Maxine AR SDK (see the roadmap in the [README](../README.md)).

Some features ship a `<Name>_dependencies.txt`. If one names other features that are not in `$DIR`, the build prints a warning listing them. Download those features as well.

### Size cost per architecture

Each GPU architecture adds the model packages of every feature that has models. In 1.3.0.0 the green screen is 8 `.engine.trtpkg` files, about 113 MB (decimal) per architecture; other features differ. Check before downloading:

```bash
ngc registry model info "nvidia/maxine/<f>:1.3.0.0_models_linux_sm<N>"
```

The build prints the model size per architecture at the end, so the cost of the finished package is visible. Package only the architectures of the machines you build for; `MAXINE_VFX_ARCHS=all` packages everything found in `$DIR`. [gpu-support.md](gpu-support.md) has the full architecture table.

### Resulting directory

The NGC CLI creates one subdirectory per download below `$DIR`:

```
$DIR/
  vfx_sdk_core_v1.3.0.0_linux/                  VFXSDK_linux_1.3.0.0.tgz  (and the Triton files)
  nvvfxgreenscreen_v1.3.0.0_lib_linux/          a .tar.gz
  nvvfxbackgroundblur_v1.3.0.0_lib_linux/       a .tar.gz
  nvvfxgreenscreen_v1.3.0.0_models_linux_sm120/ 8 .engine.trtpkg files
```

Every further feature and architecture adds one directory of the same shape.

This is exactly the layout `maxine-vfx/assemble.sh` reads in download mode.

### Several GPU architectures

To package models for more than one architecture, repeat the models download once per architecture into the same `$DIR` (for every feature that has models), then select the list:

```bash
ngc registry model download-version "nvidia/maxine/nvvfxgreenscreen:1.3.0.0_models_linux_sm89" --dest "$DIR"
maxine-vfx/configure.sh --src "$DIR" --archs "sm_120 sm_89" --write
```

See [gpu-support.md](gpu-support.md#fetching-models-for-another-gpu) for the whole procedure.

## The scripted equivalent

`maxine-vfx/download.sh` runs the same commands with your already configured `ngc`. It skips items whose directory already exists.

```bash
maxine-vfx/download.sh --list                                 # discovery only, read-only
maxine-vfx/download.sh --dry-run                              # print the commands, run nothing
maxine-vfx/download.sh                                        # sm_120 into ~/Downloads/maxine
maxine-vfx/download.sh --dest "$DIR" --archs "sm_120 sm_89"   # two architectures
maxine-vfx/download.sh --archs all --features "nvvfxgreenscreen nvvfxvideosuperres"
```

Options: `--dest DIR`, `--archs "sm_120 sm_89"` or `all` (`all` is every architecture in the [table](gpu-support.md#architectures-with-models-in-1300-linux)), `--version 1.3.0.0`, `--features "nvvfxgreenscreen nvvfxbackgroundblur"` (the default), `--list`, `--dry-run`. `--list` runs only `ngc registry model list "nvidia/maxine/nvvfx*"` and exits; with `--dry-run` it prints that command.

For every feature and every architecture the script tries `<feature>:<version>_models_linux_sm<N>`. A failed models download is reported as "models download for <feature> sm_<N> failed with status <N>", with the advice to check `ngc registry model list "nvidia/maxine/<feature>:*"`: NGC returns the same failure when the feature has no models for that architecture, and the script cannot tell the two apart. It is not fatal. A failing core or library download stops the script with a non-zero exit and prints the NGC status. After any failed download the script removes the directory of that item, so a partial download is never mistaken for a complete one, and a rerun fetches it again. Architectures are validated like `assemble.sh` does: `sm_120`, `sm120` or `120`, a number from 10 to 999 without a leading zero (`sm_075` is rejected). At the end the script prints what it fetched, what it skipped and what had no models downloaded, and the build command to run next. The script never reads `~/.ngc`, never handles the key and never passes it on a command line. It needs the NGC CLI from step 3, configured as described there.

## Alternative: an existing SDK tree

If you already have an assembled SDK tree, for example a previous user-prefix install such as `~/.local/opt/maxine/VideoFX`, you do not need the downloads. Point `MAXINE_VFX_SRC` at the tree (or at its parent directory):

```bash
cd maxine-vfx && MAXINE_VFX_SRC=~/.local/opt/maxine/VideoFX makepkg -f
```

The tree must contain `lib/libVideoFX.so`, `share/videofx_version.h` and `features/<feature>/lib/*.so`, and normally `lib/models/*.trtpkg`.

## Next step

First look at what your download holds and choose what to package. This reads `$DIR` only, without network access and without running `ngc`:

```bash
maxine-vfx/configure.sh --src "$DIR"                                   # present, offered, current selection
maxine-vfx/configure.sh --src "$DIR" --archs "sm_$SM" --features all --write
```

The second command validates the selection against what is present and writes `maxine-vfx/selection.conf`, which the PKGBUILD reads when it builds. The file is git-ignored because it holds a local path. The PKGBUILD takes each value from the environment variable of that name, else from `selection.conf`, else from its default (the source: the PKGBUILD directory; `sm_120`; `all`). Never put anything but `KEY=value` lines in it: it is parsed, not executed.

Then build:

```bash
cd maxine-vfx && makepkg -f
```

or, without `selection.conf`, with the environment variables:

```bash
cd maxine-vfx && MAXINE_VFX_SRC="$DIR" MAXINE_VFX_ARCHS="sm_$SM" MAXINE_VFX_FEATURES=all makepkg -f
```

- `MAXINE_VFX_ARCHS` selects the architectures (`sm_120`, `sm120` or `120`; a comma or space separated list; or `all`, alone). See [gpu-support.md](gpu-support.md).
- `MAXINE_VFX_FEATURES` is `all` (the default: every feature found in `$DIR` is packaged) or a comma or space separated list. A listed feature must be present, otherwise the build fails and names the missing feature and the `ngc` command that fetches it. A feature that is present but not listed is left out, and the build summary says "present, not selected". oma-broadcast, for example, needs green screen and background blur:

  ```bash
  MAXINE_VFX_FEATURES=nvvfxgreenscreen,nvvfxbackgroundblur
  ```

Install the result yourself with `sudo pacman -U`, then continue with [usage.md](usage.md).

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `ngc registry ...` returns 401, 402 or 403, an empty list, or "not authorized" | The key belongs to another account or organisation than the Developer Program access, the "NGC Catalog" service is not included, or access was not granted yet | Redo step 1 with the account that owns the key; regenerate the key with the NGC Catalog service (step 2); run `ngc config set` again with the right organisation; `ngc config current` shows what is active |
| The list shows only `_woa` or `windows` entries, or the downloaded SDK has no Linux libraries | Wrong tag: `_woa` is Windows on ARM | Use the `_linux` tags shown above |
| No `models_linux_sm<SM>` entry for your GPU | The architecture is not in the 1.3.0.0 matrix, or that feature has no model package | List the entries with step 5; the architectures with models are in [gpu-support.md](gpu-support.md) |
| The build stops with a missing models directory for a feature, architecture and NGC tag | A selected architecture has no models for a feature that has models in `$DIR` | Download the tag named in the message, or leave that architecture out of `MAXINE_VFX_ARCHS` (`configure.sh` shows what is present) |
| `download.sh` reports that `ngc` is not on PATH | The NGC CLI is not installed or `~/.local/bin` is not on `PATH` | Complete step 3 |
| `download.sh` reports "models download for ... failed with status N" | Usually the feature has no model package for that architecture (background blur has none); NGC returns the same status for any failure | Check with `ngc registry model list "nvidia/maxine/<feature>:*"`. If the tag is listed, run `download.sh` again: the failed item was removed and is retried |
| `download.sh` stops on a library download | The feature name is not an NGC name, or you have no access to it | Check the name with `download.sh --list` |
| `download.sh` skips an item | Its directory already exists in the destination | Remove that directory to download it again |
