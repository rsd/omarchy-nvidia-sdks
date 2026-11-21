# Downloading the Maxine SDKs

This guide gets the Maxine SDK files from NGC onto your disk, ready to build into a package. You need it for `maxine-vfx-sdk-local`, `maxine-ar-sdk-local` and `maxine-afx-sdk-local`. The Optical Flow SDK and TensorRT have their own guides: [optical-flow.md](optical-flow.md) and [tensorrt.md](tensorrt.md).

Maxine is NVIDIA's family of AI video and audio effects. NGC (NVIDIA GPU Cloud) is NVIDIA's online catalogue, and `ngc` is its command line tool. You download the files yourself after you accept NVIDIA's licence. This repository does not contain, and cannot provide, any of them. Read the licence terms on the NGC pages before you accept them, and see the "Licence and personal use" section of the [README](../README.md#licences-and-caveats).

An SDK is a software development kit: the libraries, headers and AI models a program uses. This page is a step-by-step guide for the Video Effects SDK 1.3.0.0 (Linux). The [Maxine AR SDK](#maxine-ar-sdk) 1.2.0.0 and the [Maxine Audio Effects SDK](#maxine-audio-effects-sdk) 3.0.0 have their own sections further down. They use the same prerequisites and the same NGC tool. Until those sections, the commands and names on this page are the Video Effects ones (`maxine-vfx/download.sh`).

For every SDK, what is downloaded, from where and whether it needs a login is listed in [What is downloaded, and from where](#what-is-downloaded-and-from-where).

There are two ways to download:

- **Automated:** [`maxine-vfx/download.sh`](../maxine-vfx/download.sh) detects your GPU, shows what it would download and how big it is, asks for confirmation, and fetches only what is missing. See [Download with one command](#download-with-one-command).
- **Manual:** the same `ngc` commands, written out. See [Download by hand](#download-by-hand).

[`scripts/setup.sh`](../scripts/setup.sh) walks through both, and through the build and installation as well ([INSTALL.md](../INSTALL.md)). Both ways need the prerequisites below, and both use your own configured NGC tool.

## Quick start

Steps 1 and 2 are yours: they need your NVIDIA login and your key.

1. **Set up NGC once.** Follow [Prerequisites](#prerequisites) steps 1 to 4 below: join the NVIDIA Developer Program, select **Get Access**, create an API key, install `ngc` and run `ngc config set`. You enter the key only at the prompt of `ngc config set`. Never paste it into a chat or a shared document.
2. **Check that NGC accepts your key.** It is read-only and never prints the key:

   ```bash
   scripts/check-ngc.sh
   ```

   *Success:* every line says `OK`. If a line says `FAIL`, read its hint, then see [Troubleshooting](#troubleshooting).
3. **Look at what would be downloaded.** Nothing is downloaded or created:

   ```bash
   maxine-vfx/download.sh --dry-run
   ```

   *Success:* it prints a table with the size and status of each item (`missing` on a first run) and the `ngc` commands it would run.
4. **Download.** It asks `Download N items (X GiB) into DIR? [y/N]`. Answer `y`:

   ```bash
   maxine-vfx/download.sh
   ```

   *Success:* the script prints the next commands, and your files are in `~/Downloads/maxine`. If it stops, run the same command again: it skips what is complete.
5. **Build and install.** Run the commands the script printed (see [Next step](#next-step)), or use `scripts/setup.sh --sdk vfx` to do both with questions. The build is `configure.sh` then `makepkg`. The install is `sudo pacman -U`, which you confirm yourself.

For the AR and Audio Effects SDKs, use `maxine-ar/download.sh` and `maxine-afx/download.sh` the same way.

## Prerequisites

| Item | Requirement | Check |
|---|---|---|
| GPU | NVIDIA, compute capability 7.5 or newer (Turing and later) | `nvidia-smi --query-gpu=name,compute_cap --format=csv` |
| Driver | 570.26 or newer | `nvidia-smi --query-gpu=driver_version --format=csv,noheader` |
| System CUDA toolkit | Not needed. The SDK bundles CUDA 12.8, cuDNN 9 and TensorRT 10 and takes only `libcuda.so.1` from the driver (`nvidia-utils`) | |
| Tools | `curl` (downloads files), `unzip` and `jq` (reads JSON), to install the NGC CLI | `sudo pacman -S --needed curl unzip jq` |
| Disk | The default download (SDK core, three feature libraries, two model sets, one architecture) is about 2.75 GiB. The extracted SDK tree is 4.4 GiB (4,671,229,191 bytes), the built package (`PKGEXT=.pkg.tar`) is about 4.4 GiB too. With all eight features and `sm_120` models the tree is 5,054,183,158 bytes (4.71 GiB) and the package about 4.7 GiB. `makepkg` needs space for its working copy as well. More features and architectures add to this: see [Sizes](#sizes) | `df -h ~` |

### 1. NVIDIA account and access (manual)

A plain NGC account is not enough. A free NVIDIA Developer Program membership gives you Maxine access. You do not need NVIDIA AI Enterprise.

1. Create or log in to an NVIDIA Developer Program account. Use this one account for NGC, the Developer Program and the API key in step 2.
2. Open <https://catalog.ngc.nvidia.com/orgs/nvidia/maxine/resources/vfx_sdk_core> ("NVIDIA Video Effects SDK Core") and log in.
3. Under "NVIDIA Developer Program", select **Get Access** and accept the terms.

The API key in step 2 must come from the account and organisation that hold this access. If it does not, downloads fail with an access error (see [Troubleshooting](#troubleshooting)).

### 2. Personal API key (manual)

1. Open <https://org.ngc.nvidia.com/setup/personal-keys> and select **Generate Personal Key**.
2. Include the **NGC Catalog** service. Choose an expiry you are comfortable with.
3. Copy the key (`nvapi-...`) at once: NGC shows it only once. Keep it out of any repository and out of your shell history. You enter it in `ngc config set` in step 4.

### 3. Install the NGC CLI

Arch has no package for the NGC command line tool, so you install NVIDIA's zip into your home directory. The first command below prints the newest version. Set that version in `NGC_VER`. Version 4.36.6 was current when this page was written.

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

`~/.local/bin` must be on your `PATH` (the list of folders the shell searches for commands). The last command prints the version when the install worked.

### 4. Configure the NGC CLI (manual)

```bash
ngc config set
```

Run this yourself and answer the prompts interactively. The key is entered here and nowhere else: it never goes into a script, a log or your shell history. The one exception is the optional Audio Effects post-install step of `scripts/setup.sh`, which can take the key for NVIDIA's `download_features.sh` (see [The key](../INSTALL.md#the-key)). You can decline it.

- API key: paste the `nvapi-...` key from step 2.
- CLI output format: `ascii`.
- org: the organisation of the account that has the Developer Program access. The prompt lists the organisations your key can see.
- team and ace: press Enter to accept the defaults.

The NGC CLI stores the key in `~/.ngc/config`. Nothing in this repository reads that file. `download.sh` and `configure.sh` never ask for, pass on or print the key. `scripts/setup.sh` asks for a key only for the optional Audio Effects post-install step, passes it only to NVIDIA's script in that script's environment, and never prints or stores it. It still never reads `~/.ngc` ([The key](../INSTALL.md#the-key)).

Check access (read-only):

```bash
ngc registry resource info nvidia/maxine/vfx_sdk_core:1.3.0.0_linux
```

This prints the details of the SDK core, which means your key and access work. If it fails, see [Troubleshooting](#troubleshooting). `scripts/check-ngc.sh` checks this and more in one run: see [Check your NGC credentials](#check-your-ngc-credentials).

## Check your NGC credentials

`scripts/check-ngc.sh` checks, read-only, that NGC accepts your key and that your account may download what you intend to. It changes nothing, downloads no SDK file and never reads `~/.ngc` itself. It prints one line per check (OK, FAIL or SKIP) and a hint after each FAIL.

```bash
scripts/check-ngc.sh                    # the NGC CLI's key, Maxine access, the Early Access models
scripts/check-ngc.sh --key --no-cli     # only a key you type at the prompt
scripts/check-ngc.sh --model nvidia/maxine/afx_speaker_focus:3.0.0-lib
```

Without options it checks the NGC CLI you configured in [step 4](#4-configure-the-ngc-cli-manual):

1. that `ngc` is installed (on `PATH`);
2. that the key configured in it is accepted by NGC (`ngc user who`);
3. that it can see the Maxine SDK core (`ngc registry resource info`), which needs Maxine access;
4. that the account is entitled to the Audio Effects SDK's Early Access models (`ngc registry model info --files`).

| Option | Effect |
|---|---|
| `--model ORG/TEAM/NAME:VERSION` | Also check access to this model; repeatable |
| `--key` | Also check a key of your own: `NGC_API_KEY` when it is set, otherwise read from standard input, without echo on a terminal (a pipe works too). A personal key (`nvapi-...`) is checked with a read-only Bearer request to NGC's API, as NVIDIA's `download_features.sh` uses it. Any other (older) key is checked through NGC's token service. Setting `NGC_API_KEY` alone also enables this check |
| `--no-cli` | Skip the NGC CLI checks and run only the `--key` check |
| `-h`, `--help` | The options |

Type the key at the prompt of `--key`. Do not write `NGC_API_KEY=... scripts/check-ngc.sh` in a terminal: your shell keeps that line in its history.

Exit status: 0 when every check passed, 1 when a check failed, 2 for a usage error.

**Results.**

| Result | Meaning | Hint |
|---|---|---|
| OK | The check passed | |
| The `ngc` command is not found | The NGC CLI is not installed or not on `PATH` | [Step 3](#3-install-the-ngc-cli) |
| The CLI has no key configured | `ngc config set` was never run | Run it yourself ([step 4](#4-configure-the-ngc-cli-manual)) |
| The key is invalid or expired | NGC answers 401 or 403, or for a personal key, 400 | Create a new key with the NGC Catalog service ([step 2](#2-personal-api-key-manual)) and run `ngc config set` |
| The key is valid, but the account has no access to a model | NGC answers HTTP 402: the account is not entitled to that model (Early Access or an entitlement) | Request access on the model's NGC page; see [HTTP 402](#http-402-the-key-works-the-account-has-no-access) |
| No access to the Maxine org/team (`nvidia/maxine`) | The account has not been given Maxine access, or the CLI's organisation is not the one that holds it | Accept the terms under Get Access ([step 1](#1-nvidia-account-and-access-manual)) with the account that owns the key, and name that organisation in `ngc config set` |
| NGC cannot be reached or answered something else | Network error, a timeout or a server error | Check the network and any proxy, then try again |

**The key stays secret.** The script never prints, logs or stores the key or a token. The key is never on a command line, so it is never an argument either (an unknown argument is not shown), and `ngc` never receives it. It is read into an unexported variable, handed to `curl` on its standard input and masked in every message that is printed. `--key` refuses to run under `bash -x` (xtrace), which would print it, and the script switches `allexport` off so that no child process inherits the key.

**What it cannot tell.** The NGC CLI has no dry run for a download. The model check asks for the model's information and file list, which is the closest read-only request, but NGC can answer that for a model whose files are gated. A model can therefore pass the CLI-side check and still answer HTTP 402 when you download it.

## Download with one command

From the root of this repository:

```bash
maxine-vfx/download.sh
```

With no options the script:

1. detects your GPU architecture with `nvidia-smi` (its `sm_` name: `sm_120` for an RTX 50 series card);
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

These commands do the same downloads as the script. The script stages each item in `DEST/.partial`, checks it and only then moves it into place. This example downloads the default set for an RTX 50 series GPU (`sm_120`) into `~/Downloads/maxine`.

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

This is exactly the layout `maxine-vfx/assemble.sh` reads. The package needs only `VFXSDK_linux_1.3.0.0.tgz` from the core. The Triton variant and the README are not used. `download.sh` produces the same directories. While it runs it also uses a temporary `.partial/` directory inside the destination, which it removes when it is empty.

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

SDK 1.3.0.0 for Linux offers eight features on NGC. The `broadcast` preset is the set a webcam pipeline needs; `all` is the eight. The mapping to NVIDIA Broadcast names is by function. NVIDIA does not document it, so treat it as a guide.

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
- **Eye Contact and Auto Frame** in NVIDIA Broadcast belong to the Maxine AR SDK, not to this Video Effects SDK. They are not part of this download. The AR SDK has its own download and package: see [Maxine AR SDK](#maxine-ar-sdk).
- Artifact reduction (`nvvfxartifactreduction`) is not on NGC for 1.3.0.0. The 1.1.0.0 Changelog says it was removed. Two more names, `nvvfxvfg` and `nvvfxframegeneration`, are not available either. NGC answers 403 for them.
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

Without `selection.conf`, use the environment variables:

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

## Maxine AR SDK

The AR SDK 1.2.0.0 holds Eye Contact (gaze redirection), face detection and landmarks, face expressions and further AR features. It is a separate NGC download and a separate package, `maxine-ar-sdk-local`. The prerequisites above apply unchanged (account, API key, NGC CLI, `ngc config set`, disk space for the tree). If an AR item answers `403`, check your access as described in [Troubleshooting](#troubleshooting).

### AR SDK: download with one command

From the root of this repository:

```bash
maxine-ar/download.sh                     # preset broadcast, for your GPU
maxine-ar/download.sh --dry-run           # the table and the commands, nothing downloaded
maxine-ar/download.sh --preset all --yes  # the seven documented features, no question
maxine-ar/download.sh --list              # the documented features, with sizes
maxine-ar/download.sh --yes --build       # download, then configure.sh --write and makepkg -f
```

It works like the Video Effects helper (see [Download with one command](#download-with-one-command)). It detects your GPU architecture, asks NGC read-only for the size of every item, prints a table, asks for confirmation, downloads only what is missing into a staging directory `.partial/`, checks each item against the size and file count NGC reported, retries failures and prints the next steps. It never runs NVIDIA's `features/install_feature.sh` (which installs into `/usr/local/ARSDK` with `sudo`), never reads `~/.ngc` and never handles the key.

| Option | Meaning |
|---|---|
| `--dest DIR` | Download directory. Default `~/Downloads/maxine/ar-sdk`, a directory of its own, so that one source holds one SDK |
| `--archs LIST` | `auto` (default, from `nvidia-smi`), `all`, or a list such as `sm_120,sm_89` |
| `--preset NAME` | `broadcast` (default) or `all` |
| `--features LIST` | NGC feature names instead of a preset. Do not combine it with `--preset` |
| `--version V` | SDK version. Default `1.2.0.0` |
| `--retries N` | Extra attempts for an item that fails. Default 2 |
| `--yes` | Do not ask. Without a terminal it is required |
| `--dry-run` | Probe, print the table and the exact `ngc` commands, change nothing |
| `--build` | After a fully successful download, run `configure.sh --write` and `makepkg -f`. It never installs and never runs `sudo` |
| `--list` | Show the documented features with sizes and exit |

The SDK core is always fetched. The library of each feature is fetched once, and its models once per architecture.

### AR SDK: features

The list is the one in the SDK's own `features/README.md` and Linux installation guide, which NVIDIA calls non-exhaustive: another name can be given with `--features`, and `download.sh` reports a name that is not on NGC as unavailable. The mapping to NVIDIA Broadcast names is by function. NVIDIA does not document it.

| NGC name | What it does | Closest NVIDIA Broadcast name | Preset |
|---|---|---|---|
| `nvargazeredirection` | Eye contact: estimates the gaze and redirects it to the camera | Eye Contact | `broadcast`, `all` |
| `nvarfaceboxdetection` | Face bounding boxes, with tracking for video | Auto Frame (closest match: it follows the face) | `broadcast`, `all` |
| `nvarlandmarkdetection` | Facial landmarks (68 or 126 points) and head pose | none (used by Eye Contact) | `broadcast`, `all` |
| `nvarfaceexpressions` | Face expression coefficients and head pose | none | `all` |
| `nvarbodydetection` | Body (person) bounding boxes | none | `all` |
| `nvarbodyposeestimation` | Body pose: keypoints and joint angles | none | `all` |
| `nvarlipsync` | Lip synchronisation: re-animates the mouth to match audio | none | `all` |

The `broadcast` preset is eye contact plus the two features its `nvARGazeRedirection_dependencies.txt` names, face box detection and landmark detection. A feature lists the features it needs in its `<Name>_dependencies.txt`, and the build prints a warning when one of them is missing or not selected.

Face expressions, body detection, body pose and lip synchronisation are optional extra downloads. Fetch them with `--preset all` or `--features`, or with the manual commands below, into the same directory. Then run `maxine-ar/configure.sh` again and rebuild. Whether a package holds them depends on what is in your download. In 1.2.0.0 Linux every AR feature has model packages. For the architectures, see [gpu-support.md](gpu-support.md#ar-and-audio-effects-sdks).

### AR SDK: download by hand

The same downloads, written out, for an RTX 50 series GPU (`sm_120`). The SDK core is an NGC resource and its tag ends in `_linux`:

```bash
ngc registry resource download-version nvidia/maxine/ar_sdk_core:1.2.0.0_linux --dest ~/Downloads/maxine/ar-sdk

# Eye contact: library and models
ngc registry model download-version nvidia/maxine/nvargazeredirection:1.2.0.0_lib_linux --dest ~/Downloads/maxine/ar-sdk
ngc registry model download-version nvidia/maxine/nvargazeredirection:1.2.0.0_models_linux_sm120 --dest ~/Downloads/maxine/ar-sdk

# The two features eye contact needs, library and models each
ngc registry model download-version nvidia/maxine/nvarfaceboxdetection:1.2.0.0_lib_linux --dest ~/Downloads/maxine/ar-sdk
ngc registry model download-version nvidia/maxine/nvarfaceboxdetection:1.2.0.0_models_linux_sm120 --dest ~/Downloads/maxine/ar-sdk
ngc registry model download-version nvidia/maxine/nvarlandmarkdetection:1.2.0.0_lib_linux --dest ~/Downloads/maxine/ar-sdk
ngc registry model download-version nvidia/maxine/nvarlandmarkdetection:1.2.0.0_models_linux_sm120 --dest ~/Downloads/maxine/ar-sdk
```

For another GPU, replace `sm120` with your architecture ([gpu-support.md](gpu-support.md#ar-and-audio-effects-sdks)). For any other feature in the [AR features](#ar-sdk-features) table, use the same two tags with its NGC name. A feature's major and minor version must equal the SDK's (1.2). To check what a package holds before downloading it, ask NGC (read-only):

```bash
ngc registry model info nvidia/maxine/nvargazeredirection:1.2.0.0_models_linux_sm120
```

The result in `~/Downloads/maxine/ar-sdk/`, which is the layout `maxine-ar/assemble.sh` reads and which `download.sh` produces too:

```
ar_sdk_core_v1.2.0.0_linux/                       ARSDK_linux_1.2.0.0.tgz and ARSDK_triton_1.2.0.0.tgz
nvargazeredirection_v1.2.0.0_lib_linux/           1 file, a .tar.gz
nvargazeredirection_v1.2.0.0_models_linux_sm120/  model files
(the same two directories for each further feature)
```

The package needs only `ARSDK_linux_1.2.0.0.tgz` from the core. The Triton client is not packaged.

### AR SDK: sizes

The model packages for `sm_120` are 92.5 MiB for eye contact, 48.0 MiB for landmark detection, 28.7 MiB for face box detection and 1.6 MiB for face expressions. `download.sh --list` prints the size of the core and of every library, and the build summary prints the model size per architecture. With four features (eye contact, face box detection, landmark detection and face expressions) and `sm_120` models the SDK tree is 4,757,681,936 bytes (4.43 GiB), of which 175 MiB are models. Most of the rest is the bundled CUDA and TensorRT libraries, which every selection carries. The built package (`PKGEXT=.pkg.tar`) is 4,758,773,760 bytes.

### AR SDK: next step

```bash
maxine-ar/configure.sh --src ~/Downloads/maxine/ar-sdk                                  # present, offered, current selection
maxine-ar/configure.sh --src ~/Downloads/maxine/ar-sdk --archs sm_120 --features all --write
cd maxine-ar && makepkg -f
sudo pacman -U maxine-ar-sdk-local-*.pkg.tar*
```

`configure.sh` reads the directory without network access and writes the git-ignored `maxine-ar/selection.conf`. The build inputs, the source layouts and the other options are in [maxine-ar/README.md](../maxine-ar/README.md). Then continue with [usage.md](usage.md#maxine-ar-sdk).

## Maxine Audio Effects SDK

The Audio Effects (AFX) SDK 3.0.0 offers speech effects: noise removal, room echo removal, both together, Studio Voice and audio super resolution. It is a separate NGC download and a separate package, `maxine-afx-sdk-local` (package version 3.0.0.12, the SDK's full version; NGC tags the downloads with the first three parts, `3.0.0`). The prerequisites above apply unchanged. If an item answers `403`, check your access as described in [Troubleshooting](#troubleshooting). `402` means the account has no access to that one model ([model status](#afx-sdk-model-status)).

### AFX SDK: download with one command

```bash
maxine-afx/download.sh                     # preset broadcast, for your GPU
maxine-afx/download.sh --dry-run           # the table and the commands, nothing downloaded
maxine-afx/download.sh --preset all --yes  # the ten effects that are not Early Access, no question
maxine-afx/download.sh --features denoiser-16k,superres-16k_to_48k --archs sm_120
maxine-afx/download.sh --list              # the known effects, with sizes
maxine-afx/download.sh --yes --build       # download, then configure.sh --write and makepkg -f
```

The behaviour is the same as for the other two helpers: detect the GPU architecture, probe sizes read-only, print a table, ask, download only what is missing through `.partial/`, verify against the size and file count NGC reported, retry, print the next steps. It never runs NVIDIA's `features/download_features.sh`, never reads `~/.ngc` and never handles the key. The options are those of the AR helper above, with these differences:

| Option | Meaning |
|---|---|
| `--dest DIR` | Download directory. Default `~/Downloads/maxine/afx-sdk` |
| `--preset NAME` | `broadcast` (default): `denoiser-48k`, `dereverb-48k`, `dereverb_denoiser-48k` and `studio_voice-48k`. `all`: the ten effects that are not Early Access |
| `--features LIST` | Effects instead of a preset, each named `<feature>-<rate>` as `--list` shows, for example `denoiser-16k`, `superres-16k_to_48k` or `speaker_focus-48k` |
| `--version V` | The NGC tag of the SDK. Default `3.0.0` |

### AFX SDK: effects

An effect is named as NVIDIA's `download_features.sh` names it, `<feature>-<rate>`. The mapping to NVIDIA Broadcast names is by function. NVIDIA does not document it.

| Feature | What it does | Closest NVIDIA Broadcast name | Rates | Preset |
|---|---|---|---|---|
| `denoiser` | Noise removal: background noise in speech | Noise Removal | `16k`, `48k` | `48k` in `broadcast`; both in `all` |
| `dereverb` | Room echo removal | Room Echo Removal | `16k`, `48k` | `48k` in `broadcast`; both in `all` |
| `dereverb_denoiser` | Noise and room echo removal in one effect | Noise Removal with Room Echo Removal | `16k`, `48k` | `48k` in `broadcast`; both in `all` |
| `studio_voice` | Studio Voice: high quality and low latency, with a mic profile | Studio Voice | `16k`, `48k` | `48k` in `broadcast`; both in `all` |
| `superres` | Audio super resolution: raises the sample rate | none | `8k_to_16k`, `16k_to_48k` | `all` |
| `speaker_focus` | Keeps the main speaker (Early Access, by request only: see [model status](#afx-sdk-model-status)) | none | `16k`, `48k` | only when named in `--features` |

The 16 kHz variants, audio super resolution and speaker focus are optional extra downloads. Fetch them with `--preset all` or `--features`, or with the manual commands below, into the same directory. Then run `maxine-afx/configure.sh` again and rebuild. The package holds every sample rate present in your download for the features you select. There is no rate setting, so leave a rate out of the download to leave it out of the package.

### AFX SDK: model status

NGC's "Linux Audio Effects SDK" collection (NVIDIA AI Enterprise / NVIDIA Developer Program) lists eight models. The SDK resource is `nvidia/maxine/maxine_linux_audio_effects_sdk` 3.0.0. A model's versions are `3.0.0-lib` (the library) and `3.0.0-<rate>-sm<N>` (models per sample rate and architecture, for example `3.0.0-16k_to_48k-sm120` for `afx_superres`).

| Model | Status | Access |
|---|---|---|
| `afx_denoiser`, `afx_dereverb`, `afx_dereverb_denoiser`, `afx_studio_voice`, `afx_superres` | Generally available | Your NVIDIA Developer Program access |
| `afx_speaker_focus` | NVIDIA Maxine Early Access | "Available by request only": request it at <https://catalog.ngc.nvidia.com/orgs/nvidia/teams/maxine/models/afx_speaker_focus>. Without it NGC answers HTTP 402 |
| `afx_aec` (2.1.0), `afx_voice_font` (2.1.0-sm86) | Deprecated, not in SDK 3.0 | Not used by this recipe |

HTTP 402 means that your key authenticated, but the account is not entitled to that model (Early Access or an entitlement). Retrying cannot help. `maxine-afx/download.sh` skips such an effect without retrying and removes what it had already fetched for it in that run (what was in the directory before the run stays). It lists the skipped effects at the end, with the page where to request access, and leaves them out of the next steps. That alone does not fail the run: the exit status is 0, and 1 only when every chosen effect was refused, so that there is nothing to build. The effects that were not refused are downloaded as usual. `--list` shows "needs access" for such a model. [HTTP 402](#http-402-the-key-works-the-account-has-no-access) has the error text and the fix, and `scripts/check-ngc.sh` can tell you beforehand ([Check your NGC credentials](#check-your-ngc-credentials)).

### AFX SDK: download by hand

The NGC names are those NVIDIA's `features/download_features.sh` uses. For `denoiser` at 48 kHz on an RTX 50 series GPU (`sm_120`):

```bash
# The SDK core is an NGC resource
ngc registry resource download-version nvidia/maxine/maxine_linux_audio_effects_sdk:3.0.0 --dest ~/Downloads/maxine/afx-sdk

# A feature's library (once per feature), then its models per sample rate and architecture
ngc registry model download-version nvidia/maxine/afx_denoiser:3.0.0-lib --dest ~/Downloads/maxine/afx-sdk
ngc registry model download-version nvidia/maxine/afx_denoiser:3.0.0-48k-sm120 --dest ~/Downloads/maxine/afx-sdk
```

Repeat the last two commands with `afx_dereverb`, `afx_dereverb_denoiser` and `afx_studio_voice` for the rest of the `broadcast` preset. For another rate, replace `48k` (`16k`, or `8k_to_16k` and `16k_to_48k` for `afx_superres`). For another GPU, replace `sm120` ([gpu-support.md](gpu-support.md#ar-and-audio-effects-sdks)). If a models tag does not exist, that effect has no model package for that rate and architecture. To check an item before downloading it, ask NGC (read-only):

```bash
ngc registry model info nvidia/maxine/afx_denoiser:3.0.0-48k-sm120
```

`download.sh --list` and `--dry-run` do the same probing for you and report a name that NGC does not know as unavailable, so use them to check a name before relying on it. The result in `~/Downloads/maxine/afx-sdk/`, the layout `maxine-afx/assemble.sh` reads:

```
maxine_linux_audio_effects_sdk_v3.0.0/       NVIDIA_AFX_SDK_Linux_3.0.0.12.tar.gz
afx_denoiser_v3.0.0-lib/                     1 file, a .tar.gz
afx_denoiser_v3.0.0-48k-sm120/               .trtpkg model files, each with a .md5
(the same library and models directories for each further feature)
```

The build checks each model against its `.md5` file and stops on a mismatch, which means a corrupted or interrupted download. Any other `afx_*_v*` directory in the source stops the build.

### AFX SDK: sizes

NGC reports the size of each item, and `download.sh --list` prints it. For the four features at 48 kHz and `sm_120` models, the assembled SDK tree is about 3.8 GiB, of which the models are about 1.5 GiB, and the built package is about 3.75 GiB uncompressed (`PKGEXT=.pkg.tar`). Each further architecture and each further sample rate adds model packages.

### AFX SDK: next step

```bash
maxine-afx/configure.sh --src ~/Downloads/maxine/afx-sdk                                 # present, offered, current selection
maxine-afx/configure.sh --src ~/Downloads/maxine/afx-sdk --archs sm_120 --features all --write
cd maxine-afx && PKGEXT=.pkg.tar makepkg -f
sudo pacman -U maxine-afx-sdk-local-*.pkg.tar*
```

`configure.sh` reads the directory without network access and writes the git-ignored `maxine-afx/selection.conf`. The build inputs, the source layouts and the other options are in [maxine-afx/README.md](../maxine-afx/README.md). Then continue with [usage.md](usage.md#maxine-audio-effects-sdk).

## What is downloaded, and from where

The table lists every file that the recipes use. It was checked on 2026-11-14 with HEAD requests and with anonymous NGC catalogue queries (no API key). NVIDIA changes its catalogue, so check the current state before you rely on a size.

| Item | Current method | Public, no login? | Size | Checksum pinned in the recipe |
|---|---|---|---|---|
| TensorRT 11.4.0.106 archive (Linux x86_64, CUDA 13.4) | automatic (makepkg), or your own copy | yes: developer.nvidia.com → developer.download.nvidia.com, HTTP 200 | 3,725,547,403 bytes | yes, SHA-256 |
| Optical Flow SDK 5.0.7 zip | browser, NVIDIA Developer Program login | no: the download link redirects to the login page | not shown without login | no (NVIDIA publishes none; `configure.sh --write` records yours) |
| Video Effects SDK core `nvidia/maxine/vfx_sdk_core:1.3.0.0_linux` | NGC CLI with your API key | no: catalogue says not public, no guest download | not shown anonymously (`ngc ... info` with your key; see [Sizes](#sizes)) | no (size and file counts compared with NGC) |
| AR SDK core `nvidia/maxine/ar_sdk_core:1.2.0.0_linux` | NGC CLI with key | no (same) | as above | no |
| Audio Effects SDK core `nvidia/maxine/maxine_linux_audio_effects_sdk:3.0.0` | NGC CLI with key | no (same) | about 1.5 GB (NGC's figure for 3.0.0, 1,501,636,190 bytes) | no |
| Video Effects features, `nvidia/maxine/<feature>:1.3.0.0_lib_linux` and `_models_linux_sm<N>` (8 features; models for green screen, denoising, relighting) | NGC CLI with key | no: the catalogue does not list them anonymously (HTTP 401/404 without a key) | see [Sizes](#sizes) | no; the models' `.trtpkg.md5` files from NVIDIA are checked |
| AR SDK features, `nvidia/maxine/<feature>:1.2.0.0_lib_linux` / `_models_linux_sm<N>` (7 features) | NGC CLI with key | no (same) | see [AR SDK: sizes](#ar-sdk-sizes) | no; NVIDIA's `.md5` files checked |
| Audio Effects effects, `nvidia/maxine/afx_<effect>:3.0.0-lib` and `3.0.0-<rate>-sm<N>` | NGC CLI with key | no (same) | see [AFX SDK: sizes](#afx-sdk-sizes) | no; NVIDIA's `.md5` files checked |
| Audio Effects speaker focus (Early Access) | request access on NGC; may answer HTTP 402 | no | — | no; stays manual or skipped |
| AR SDK Early Access collection | request only, not downloaded by any script | no | — | — |
| NGC CLI 4.36.6 (`ngccli_linux.zip`) | you download it ([step 3](#3-install-the-ngc-cli)) | yes: public, guest download allowed | 59,137,746 bytes | no (checked against the md5 file shipped inside the zip) |

The sizes that NGC shows anonymously for the Video Effects and AR cores belong only to their newest `_woa` (Windows on ARM) versions, so they are not quoted here.

Only TensorRT is both public and pinned, so only TensorRT is downloaded automatically. The Maxine SDKs need your NGC key, and the Optical Flow SDK needs a login.

## Troubleshooting

The entries below use the Video Effects names. The same causes and fixes apply to `maxine-ar/download.sh` and `maxine-afx/download.sh`: the helpers report the same table statuses, `403` and "could not be found" mean the same thing, an interrupted run is repeated with the same command, and `--list` shows the names they know.

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
- **`402`** is a different case: the key and the Maxine access are fine, and the account has no entitlement to one model. See [HTTP 402](#http-402-the-key-works-the-account-has-no-access).
- **Not sure which of these it is?** Run `scripts/check-ngc.sh`. It separates a missing key, an invalid or expired key, missing Maxine access and a missing entitlement ([Check your NGC credentials](#check-your-ngc-credentials)).
- **Only `_woa` or `windows` entries, or an SDK with no Linux libraries.** Wrong tag: `_woa` is Windows on ARM. Use the `_linux` tags shown above.

### HTTP 402: the key works, the account has no access

The error looks like this, from NVIDIA's `features/download_features.sh` (`scripts/setup.sh` runs it after an install) or from the NGC CLI:

```
Could not download file (status: 402): https://api.ngc.nvidia.com/v2/org/nvidia/team/maxine/models/afx_speaker_focus/3.0.0-lib/files
```

HTTP 402 is not a key problem: the key authenticated, but the account is not entitled to that model (Early Access or an entitlement). Here the model is `afx_speaker_focus`, which is part of NVIDIA Maxine Early Access and available by request only. Request access at its page, <https://catalog.ngc.nvidia.com/orgs/nvidia/teams/maxine/models/afx_speaker_focus>. The same applies to any other model named in the URL, on its own NGC page.

- `maxine-afx/download.sh` and `scripts/setup.sh` skip that effect, say which one and where to ask, and go on with the others. The rest of the setup is not affected. Run the command again once access is granted.
- You do not need to change the key or the CLI's organisation.
- Leave speaker focus out until you have access: `--features-afx all` and `--preset all` already do.
- `scripts/check-ngc.sh` shows the state beforehand. It cannot see every case, because the NGC CLI has no download dry run.

### The architecture is wrong or has no models

`download.sh` takes the architecture from `nvidia-smi --query-gpu=compute_cap --format=csv,noheader`. The value `12.0` becomes `sm_120`, `8.6` becomes `sm_86` and `10.0` becomes `sm_100`: remove the dot. A GPU below 7.5 is not supported, and the script stops.

- To use another architecture than the one detected, pass it: `download.sh --archs sm_89`. This is also needed when `nvidia-smi` is not available.
- If the table says "no model package" for a feature, NGC has no models for that feature and architecture. In 1.3.0.0, background blur, video super resolution, upscale, TrueHDR and video frame generation have no model package. For green screen, denoising and relighting, check that your architecture is in the [table of architectures](gpu-support.md#architectures-with-models-in-1300-linux). A value that is not in the table, such as 8.7 or 12.1, has no exact model package.
- The build stops with a missing models directory for a feature, architecture and NGC tag when a selected architecture has no models for a feature that has models in your download. Download the tag named in the message, or leave that architecture out of `MAXINE_VFX_ARCHS` (`configure.sh` shows what is present).

### The download was interrupted

Run the same `download.sh` command again. Items that are complete (the file count and size match what NGC reports) are skipped, and incomplete ones are downloaded again. A failed item is also retried automatically, `--retries` times. The `.partial/` directory in the destination is the script's staging area. It is safe to delete when the script is not running.

For a manual download, delete the incomplete directory and run the command again.

### `ngc` is not on PATH

`download.sh` stops and says so. Complete [step 3](#3-install-the-ngc-cli). The CLI is linked into `~/.local/bin`, which must be on your `PATH`. Check with `command -v ngc`.

### Other

| Symptom | Cause | Fix |
|---|---|---|
| `download.sh` says to pass `--yes` | There is no terminal to ask the confirmation on | Add `--yes`, or run it from a terminal |
| `download.sh` says to pass `--archs` | `nvidia-smi` is missing or failed | Pass your architecture, for example `--archs sm_120` |
| `download.sh` reports a feature as "unavailable (unknown name or no access)" | The feature name is not on NGC for this version, or you have no access to it | Check the name with `download.sh --list` |
| `download.sh` reports an item as "probe failed: ..." | NGC answered the `info` request with an error other than 403 or "could not be found", such as a timeout, a server error or a rate limit | Run the script again later. The item is not downloaded, the run fails and `--build` does not run |
| A feature has no models in the table | It has no model package for that architecture | Nothing to fix. See above |
