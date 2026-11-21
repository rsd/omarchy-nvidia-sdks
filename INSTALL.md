# Install the NVIDIA SDK packages

This guide builds and installs the local Arch Linux packages for the NVIDIA SDKs (software development kits: libraries, headers and AI models). You download each SDK from NVIDIA yourself, except TensorRT, which `makepkg` can download for you. The guided script `scripts/setup.sh` does the rest and asks before every step that changes anything.

| Package | SDK | AUR |
|---|---|---|
| `maxine-vfx-sdk-local` | Maxine Video Effects 1.3.0.0 | `maxine-vfx-sdk-local` |
| `maxine-ar-sdk-local` | Maxine AR 1.2.0.0 | `maxine-ar-sdk-local` |
| `maxine-afx-sdk-local` | Maxine Audio Effects 3.0.0 (package version 3.0.0.12) | `maxine-afx-sdk-local` |
| `nvidia-optical-flow-sdk-local` | Optical Flow 5.0.7 | `nvidia-optical-flow-sdk-local` |
| `nvidia-tensorrt-sdk-local` | TensorRT 11.4.0.106 | not on the AUR |

Each AUR package is a recipe only. It builds from files that you download from NVIDIA. See [docs/aur.md](docs/aur.md).

## Licence and what you download

- **Nothing from NVIDIA is redistributed.** This repository holds only the build recipes: PKGBUILDs, scripts, documentation and the source of a small compatibility shim.
- **You accept NVIDIA's licence, and you download the SDK yourself**, with your own account where NVIDIA asks for one: from NVIDIA NGC for the Maxine SDKs, and in a browser from NVIDIA's developer site for the Optical Flow SDK. TensorRT is also served by NVIDIA without a login, and `makepkg` can download it for you under NVIDIA's TensorRT Software License Agreement, or you can download it in a browser. Apart from that download, the recipes only automate what happens after your download.
- **The built package contains NVIDIA software and is for your own machine only.** Never upload it to a package repository, to the AUR as a binary, to a release page, or share it in any other way.
- NVIDIA does not support this configuration.
- This is not legal advice. Read the licence you accept.

The full terms are in [Licences and caveats](README.md#licences-and-caveats).

## Before you start

You need:

- **An NVIDIA RTX GPU**, Turing (RTX 20 series) or newer. See [docs/gpu-support.md](docs/gpu-support.md).
- **Arch Linux or an Arch-based distribution** (for example Omarchy). It needs `pacman` (the package manager), `makepkg` (builds a package from a `PKGBUILD` recipe), and `fakeroot` and `bsdtar` (helper tools `makepkg` uses). This command installs them:

  ```bash
  sudo pacman -S --needed base-devel fakeroot libarchive
  ```

- **The NVIDIA driver**, version 570.26 or newer, so that `nvidia-smi` works. Check with `nvidia-smi`.
- **Free disk space**: about 3 GiB for a download and about 13 GiB for one build. A GiB is about a billion bytes.
- **A free NVIDIA Developer Program account.** You log in with it to download the Maxine and Optical Flow SDKs. TensorRT needs no login.
- **For the three Maxine SDKs only:** the NGC command line tool and a personal API key. NGC (NVIDIA GPU Cloud) is NVIDIA's online catalogue where it publishes the Maxine SDKs. The API key is the password the tool uses. Step 3 of [Install with the guided script](#install-with-the-guided-script) explains how to get both.
- **For TensorRT only:** Arch's `cuda` package, version 13.4 or newer and below 14. `pacman -U` pulls it in when it is missing.

The Optical Flow SDK and TensorRT need no NGC. The Optical Flow SDK is one file that you download in a browser. TensorRT is one file that `scripts/setup.sh` or `makepkg` downloads from NVIDIA, or that you download in a browser.

## What you do yourself

The script never logs in to NGC, never accepts a licence and never runs `ngc config`. Accepting the licence and creating the key are acts of your own account, with your own agreement to NVIDIA's terms. These steps stay with you:

- Log in to NVIDIA, accept the licence and download a file in a browser.
- Create the NGC API key and enter it with `ngc config set`. Never paste a key into a chat or a shared document.
- Answer `y` to a `sudo` command.

The script reads a key only from the `NGC_API_KEY` environment variable or from a hidden prompt, and it never prints, logs or stores it. See [The key](#the-key).

## Install with the guided script

Every command runs from the root of this repository.

1. **Get this repository.**

   ```bash
   git clone https://github.com/rsd/omarchy-nvidia-sdks.git
   cd omarchy-nvidia-sdks
   ```

2. **Look first.** A dry run checks your machine and prints every command it would run. It changes nothing and asks nothing.

   ```bash
   scripts/setup.sh --dry-run
   ```

   *Success:* the output ends with `Dry run: nothing was asked, run or written.` A line with `WARNING` names something missing and how to fix it (for example a missing `base-devel`). Fix those, then run it again.

3. **Download the SDK. This step is yours.** Pick the SDK or SDKs first:

   | You want | `--sdk` key | How you get it |
   |---|---|---|
   | AI green screen, background blur, video noise removal | `vfx` | NGC |
   | Eye contact, face detection | `ar` | NGC |
   | Microphone noise and room echo removal, Studio Voice | `afx` | NGC |
   | Optical Flow | `of` | Browser |
   | TensorRT | `trt` | Automatic (or a browser download you save in `~/Downloads`) |

   - **Maxine SDKs (`vfx`, `ar`, `afx`):** set up NGC once.
     1. Log in to your NVIDIA Developer Program account.
     2. On the SDK's NGC catalogue page, select **Get Access** and accept NVIDIA's licence.
     3. Create a personal API key that includes the **NGC Catalog** service.
     4. Install the NGC command line tool, `ngc`.
     5. Run `ngc config set` yourself and paste the key at its prompt.

     [docs/download.md](docs/download.md#prerequisites) has the exact links and commands. The download itself (`download.sh`) runs later, in step 5.
   - **Optical Flow (`of`):** open the download page in a browser, log in, accept the licence and save `optical_flow_sdk_5.0.7.zip` in `~/Downloads`. See [docs/optical-flow.md](docs/optical-flow.md#download).
   - **TensorRT (`trt`):** nothing to do if you have no copy. When `scripts/setup.sh` finds none in `~/Downloads`, `makepkg` downloads it from NVIDIA with no login, during the build. Read NVIDIA's TensorRT licence first: the script names it, and by building you accept it. To use your own copy, download `TensorRT-Enterprise-11.4.0.106-Linux-x86_64-cuda-13.4-Release-external.tar.zst` in a browser and save it in `~/Downloads`. Take the Linux x86_64 build, not ARM. See [docs/tensorrt.md](docs/tensorrt.md#download).

   *Success:* for NGC, `scripts/check-ngc.sh` (next step) accepts your key. For a browser download, the file is in `~/Downloads`.

4. **Check your NGC key (Maxine SDKs only).** This is read-only. It never prints, logs or stores a key.

   ```bash
   scripts/check-ngc.sh
   ```

   *Success:* every line says `OK` and the exit status is 0. After each `FAIL` it prints a hint. One `FAIL` is harmless if you do not need that effect: HTTP 402 for the Early Access model `afx_speaker_focus` means your key works but your account lacks that approval. [Check your NGC credentials](#check-your-ngc-credentials) lists the results.

5. **Run the guided setup.** Name the SDKs you chose. The script asks before every step that changes anything (the default answer is No) and prints each command it runs. It finds your download, offers to run `download.sh` for a Maxine SDK, builds the package with `makepkg`, installs it with `sudo pacman -U`, and checks the result.

   ```bash
   scripts/setup.sh --sdk vfx
   ```

   Replace `vfx` with `ar`, `afx`, `of`, `trt`, or a comma separated list such as `vfx,afx`. The build takes several minutes, and the installed package is several GiB.

   *Success:* the `== 7. Check` section shows `ok` in every column for your SDK and the script exits with status 0 (`echo $?` prints `0`). Section `== 8. Undo` then prints the commands that remove what it installed.

6. **Use it.** A program loads the package's environment file and, for Maxine, preloads a small shim. [docs/usage.md](docs/usage.md) shows how.

The script is safe to run again. It detects and keeps what is done: a valid download, a `selection.conf`, a built package, the installed version, features already copied in.

### Script options

| Option | Effect |
|---|---|
| `--sdk LIST` | The SDKs to set up, comma separated: `vfx`, `ar`, `afx`, `of`, `trt`, `maxineea`, or `all`. Without it the script asks about each one (default answer: No). `maxineea` is a placeholder that only prints how to request Early Access (see [The Maxine Early Access entry](#the-maxine-early-access-entry)); `all` skips it |
| `--features-KEY LIST` | The optional downloads of one SDK that has any (`--features-vfx`, `--features-ar`, `--features-afx`; KEY as in `--sdk`), comma separated: names from the SDK's list, their numbers, or `all`. `all` is every effect except those marked "access required" (see [Effects that need access](#effects-that-need-access)), which you choose by name or number. Without the option the script shows the list and asks: numbers or names, `all`, or Enter for the default (marked `[x]`). A dry run takes the default. The Optical Flow SDK and TensorRT have no optional features. `scripts/setup.sh --help` prints every SDK's feature list |
| `--src-KEY PATH` | Where the download of one SDK is (`--src-vfx`, `--src-ar`, `--src-afx`, `--src-of`, `--src-trt`). For an NGC SDK, its download directory. For an SDK downloaded as one file, that file, the directory that holds it or its extracted tree. It comes before the `*_SRC` variable, the package's `selection.conf` and the default location |
| `--dry-run`, `--print-commands` | Read-only: check, detect and print the commands; ask nothing, change nothing |
| `-h`, `--help` | Print the options, where each SDK comes from and the lists of optional features of each SDK |

Examples:

```bash
scripts/setup.sh --dry-run                                        # look first: every SDK, the default selection
scripts/setup.sh --sdk afx --features-afx all                     # Audio Effects, every effect that is not "access required"
scripts/setup.sh --sdk trt                                        # TensorRT only
scripts/setup.sh --sdk afx --features-afx superres-16k_to_48k     # one named effect instead of the default
scripts/setup.sh --sdk vfx,afx --dry-run                          # look at two SDKs
scripts/setup.sh --sdk afx --features-afx 2,4,11                  # by number; 11 needs access (see below)
```

Without `--sdk` the script asks, for each SDK, whether to set it up (Video Effects, AR, Audio Effects, Optical Flow, TensorRT and the Early Access entry). An empty answer or the end of input means No.

**Feature names.** `scripts/setup.sh --help` is the reference. The names are those of the SDK's `download.sh --features`. For the Video Effects and AR SDKs they are the NGC names of the features (`nvvfxgreenscreen`, `nvargazeredirection`, and so on; see [docs/download.md](docs/download.md#features) and [docs/download.md](docs/download.md#ar-sdk-features)). For the Audio Effects SDK each effect is `<feature>-<rate>`:

| Name | Effect | Default |
|---|---|---|
| `denoiser-16k`, `denoiser-48k` | Noise removal | 48k |
| `dereverb-16k`, `dereverb-48k` | Room echo removal | 48k |
| `dereverb_denoiser-16k`, `dereverb_denoiser-48k` | Noise and room echo removal in one effect | 48k |
| `superres-8k_to_16k`, `superres-16k_to_48k` | Audio super resolution | none |
| `studio_voice-16k`, `studio_voice-48k` | Studio Voice | 48k |
| `speaker_focus-16k`, `speaker_focus-48k` | Speaker focus (access required: Maxine Early Access) | none |

Environment variables:

| Variable | Meaning |
|---|---|
| `MAXINE_VFX_SRC`, `MAXINE_AR_SRC`, `MAXINE_AFX_SRC`, `NVIDIA_OF_SRC`, `NVIDIA_TRT_SRC` | The download of an SDK, as for `configure.sh` and `makepkg`. Without them the script uses the location in the package's `selection.conf`, then the default (`~/Downloads/maxine`, `~/Downloads/maxine/ar-sdk`, `~/Downloads/maxine/afx-sdk`, and `~/Downloads` for the Optical Flow SDK and TensorRT) |
| `NGC_API_KEY` | The key for NVIDIA's `download_features.sh`, used only by the Audio Effects post-install step (see [The key](#the-key)) |
| `MAXINE_SETUP_ROOT` | A prefix for `/opt` and `/usr/share`. It exists for the script's own tests; leave it empty |

The exit status is 0 when the run is done (an SDK you skipped is not a failure), 1 for a hard blocker or a failed step, and 2 for a usage error.

## Install one package by hand

The guided script runs these commands for you, and prints each one before it runs it. Run them yourself if you prefer. Only `scripts/setup.sh` runs `sudo` or installs anything on its own, and it asks first. `download.sh`, `configure.sh` and the PKGBUILDs never do.

### Maxine Video Effects

1. Download the SDK files from NGC:

   ```bash
   maxine-vfx/download.sh
   ```

   The script detects your GPU architecture, asks NGC what exists, prints a table of what it would download and how big it is, and asks for confirmation. It downloads only what is missing, verifies the result and retries failures. Use `--dry-run` to look without downloading, `--preset all` for every feature, and `--yes` to skip the question. The options are in [docs/download.md](docs/download.md#download-with-one-command). The result is one directory, by default `~/Downloads/maxine`. To type the `ngc` commands yourself, see [docs/download.md](docs/download.md#download-by-hand).

2. Choose your features and architectures, and build the package. `download.sh` prints these commands with your paths filled in, and `--build` runs them for you:

   ```bash
   maxine-vfx/configure.sh --src ~/Downloads/maxine --archs sm_120 --features all --write
   cd maxine-vfx && makepkg -f
   ```

   `configure.sh` saves the choice in `maxine-vfx/selection.conf`, and `makepkg` reads it. Replace `sm_120` with your GPU's architecture: the number from `nvidia-smi --query-gpu=compute_cap --format=csv,noheader`, without the dot, after `sm_` (see [docs/gpu-support.md](docs/gpu-support.md)). Without `selection.conf` you can pass the same choice in the environment:

   ```bash
   MAXINE_VFX_SRC=~/Downloads/maxine MAXINE_VFX_ARCHS=sm_120 MAXINE_VFX_FEATURES=all makepkg -f
   ```

3. Install the package (run it in `maxine-vfx/`, where `makepkg` left it):

   ```bash
   sudo pacman -U maxine-vfx-sdk-local-*.pkg.tar*
   ```

The build inputs (`MAXINE_VFX_SRC`, `MAXINE_VFX_ARCHS`, `MAXINE_VFX_FEATURES`) are in [maxine-vfx/README.md](maxine-vfx/README.md). To choose features and GPUs, see [Choose features and architectures](#choose-features-and-architectures).

### Maxine AR and Audio Effects

`maxine-ar/` and `maxine-afx/` have the same layout, options and steps as `maxine-vfx/`. Each has its own download directory, by default `~/Downloads/maxine/ar-sdk` and `~/Downloads/maxine/afx-sdk`, so that one source directory holds one SDK.

```bash
# AR SDK: eye contact, face box and landmark detection
maxine-ar/download.sh
maxine-ar/configure.sh --src ~/Downloads/maxine/ar-sdk --archs sm_120 --features all --write
cd maxine-ar && makepkg -f
sudo pacman -U maxine-ar-sdk-local-*.pkg.tar*

# Audio Effects SDK: noise removal, room echo removal and Studio Voice at 48 kHz
cd ..   # back to the repository root
maxine-afx/download.sh
maxine-afx/configure.sh --src ~/Downloads/maxine/afx-sdk --archs sm_120 --features all --write
cd maxine-afx && PKGEXT=.pkg.tar makepkg -f
sudo pacman -U maxine-afx-sdk-local-*.pkg.tar*
```

The build inputs are `MAXINE_AR_SRC`, `MAXINE_AR_ARCHS` and `MAXINE_AR_FEATURES`, and `MAXINE_AFX_SRC`, `MAXINE_AFX_ARCHS` and `MAXINE_AFX_FEATURES`. The Audio Effects package has no sample-rate input: every sample rate present in your download is packaged. Each package's README is the reference: [maxine-ar/README.md](maxine-ar/README.md) and [maxine-afx/README.md](maxine-afx/README.md).

| Package | Features | NGC names |
|---|---|---|
| `maxine-ar-sdk-local` | Eye contact (`nvargazeredirection`), face box detection (`nvarfaceboxdetection`), facial landmarks (`nvarlandmarkdetection`), face expressions (`nvarfaceexpressions`); also offered: body detection, body pose and lip synchronisation (`nvarbodydetection`, `nvarbodyposeestimation`, `nvarlipsync`) | `nvidia/maxine/<feature>` |
| `maxine-afx-sdk-local` | Noise removal (`denoiser`), room echo removal (`dereverb`), both in one (`dereverb_denoiser`), Studio Voice (`studio_voice`); also offered: audio super resolution (`superres`), the 16 kHz variants and speaker focus (Early Access, by request only) | `nvidia/maxine/afx_<feature>` |

Eye Contact and Auto Frame in NVIDIA Broadcast belong to the AR SDK, not to the Video Effects SDK. The names, preset contents, manual `ngc` commands and sizes are in [docs/download.md](docs/download.md#maxine-ar-sdk) for the AR SDK and [docs/download.md](docs/download.md#maxine-audio-effects-sdk) for the Audio Effects SDK. The GPU architectures are in [docs/gpu-support.md](docs/gpu-support.md#ar-and-audio-effects-sdks).

### Optical Flow

Download `optical_flow_sdk_5.0.7.zip` in a browser first ([docs/optical-flow.md](docs/optical-flow.md#download)). Then:

```bash
cd nvidia-optical-flow
./configure.sh --src ~/Downloads/optical_flow_sdk_5.0.7.zip --write
makepkg -f
sudo pacman -U nvidia-optical-flow-sdk-local-5.0.7-*-x86_64.pkg.tar*
```

### TensorRT

`makepkg` downloads the archive when it finds none. Otherwise save your own copy in `~/Downloads` ([docs/tensorrt.md](docs/tensorrt.md#download)). Then:

```bash
cd nvidia-tensorrt
./configure.sh --src ~/Downloads --write   # optional: checks your file and saves it
PKGEXT=.pkg.tar makepkg -f                 # downloads the archive when no source is found
sudo pacman -U nvidia-tensorrt-sdk-local-11.4.0.106-2-x86_64.pkg.tar
```

The TensorRT package conflicts with the AUR `tensorrt` package. See [docs/tensorrt.md](docs/tensorrt.md#relation-to-the-aurs-tensorrt-package).

### Choose features and architectures

A GPU architecture is the generation of your GPU, written `sm_` plus its compute capability without the dot: `sm_120` for an RTX 50 series card. Run the selection helper on your download directory to see what you have and what the SDK offers:

```bash
maxine-vfx/configure.sh --src ~/Downloads/maxine
```

It reads the directory without network access and without running `ngc`, and prints:

- the features and GPU architectures **present** in your download, and the SDK version;
- the features the SDK **offers** and the GPU architectures that have models for 1.3.0.0 Linux, with the ones you already have marked;
- your current selection and the commands to change it or to fetch more.

SDK 1.3.0.0 for Linux offers eight features on NGC:

| Feature | NGC name | Preset |
|---|---|---|
| AI green screen | `nvvfxgreenscreen` | broadcast, all |
| Background blur | `nvvfxbackgroundblur` | broadcast, all |
| Video noise removal | `nvvfxdenoising` | broadcast, all |
| Video relighting | `nvvfxrelighting` | all |
| Video super resolution | `nvvfxvideosuperres` | all |
| Video upscaling | `nvvfxupscale` | all |
| SDR to HDR (TrueHDR) | `nvvfxtruehdr` | all |
| Video frame generation | `nvvfxvideoframegeneration` | all |

The `broadcast` preset is the default of `download.sh`. Model packages exist only for green screen, denoising and relighting. Artifact reduction (`nvvfxartifactreduction`) is not on NGC for 1.3.0.0. What each feature does, its closest NVIDIA Broadcast name and its download size are in [docs/download.md](docs/download.md#features). NGC hides the Maxine items from `ngc registry model list "nvidia/maxine/nvvfx*"`, which prints an empty table, so use `maxine-vfx/download.sh --list` to see what is available.

To save a selection:

```bash
maxine-vfx/configure.sh --src ~/Downloads/maxine --archs sm_120 --features all --write
```

This checks the selection against what is present (a feature or architecture you have not downloaded is an error, and the message names the command that fetches it) and writes `maxine-vfx/selection.conf`. Git ignores the file because it holds a local path. The PKGBUILD reads it when it builds. It is parsed as plain `KEY=value` lines and never executed. An environment variable overrides the file, and the file overrides the built-in default. `configure.sh --show` prints the current file, and `--conf FILE` makes `configure.sh` read and write another file, such as the `selection.conf` of an AUR clone ([docs/aur.md](docs/aur.md)).

To fetch more features or architectures, run `maxine-vfx/download.sh` again with `--features` or `--archs`, then `configure.sh` and `makepkg` again. Which GPUs are supported, how to find your architecture and how to fetch models for another GPU are in [docs/gpu-support.md](docs/gpu-support.md).

- **Features.** `MAXINE_VFX_FEATURES` is `all` (the default: every feature found in your download is packaged) or a list such as `nvvfxgreenscreen,nvvfxbackgroundblur`: exactly those are packaged, and each must be present. To add a feature, download its library and models into the same directory (`download.sh --features ...`, or your own `ngc`), then rebuild. The steps are in [docs/download.md](docs/download.md#more-features).
- **GPU architectures.** `MAXINE_VFX_ARCHS` takes a list (`"sm_120 sm_89"`) or `all`. The SDK needs a Tensor-core GPU, Turing or newer. Each architecture adds the model packages of every feature that has models: for `sm_120` that is about 113 MiB for green screen, 3.7 MiB for denoising and 79 MiB for relighting. The sizes per architecture are in [docs/gpu-support.md](docs/gpu-support.md#size-cost-per-architecture).
- **Sizes** in these documents are stated in MiB or GiB (2^20 and 2^30 bytes), or in GB (10^9 bytes), explicitly. The default download for `sm_120` is about 2.75 GiB, of which the SDK core is 2.63 GiB. The assembled SDK tree is 4.4 GiB (4,671,229,191 bytes) and the built package (`PKGEXT=.pkg.tar`) is about 4.4 GiB too. With all eight features and `sm_120` models the assembled tree is 5,054,183,158 bytes (4.71 GiB) and the package is about 4.7 GiB (`PKGEXT=.pkg.tar`); the five features outside the default add 326,922,413 bytes (about 312 MiB) to the download.

## Check your NGC credentials

Before a large download, `scripts/check-ngc.sh` tells you whether NGC accepts your key and what your account may download. It is read-only, and it never prints, logs or stores a key or a token:

```bash
scripts/check-ngc.sh                 # the NGC CLI's key, Maxine access, the Early Access models
scripts/check-ngc.sh --key --no-cli  # only a key you type at the prompt
```

It prints one line per check (OK, FAIL or SKIP) and a hint after each FAIL. It exits 0 when every check passed, 1 when one failed and 2 for a usage error. Type a key at the prompt of `--key`, which does not echo it. Do not put the key on the command line as `NGC_API_KEY=... scripts/check-ngc.sh`: it stays in your shell history. What is checked, what each result means and the options are in [docs/download.md](docs/download.md#check-your-ngc-credentials).

## Check that it works

The guided script checks every install it makes. Its `== 7. Check` section is read-only. For each SDK it checks the installed package, the environment file, the library path, `ldd` of the core library with that path, and the models for your architecture, and it prints one line per SDK with notes for anything missing. The checks differ by SDK:

- **Maxine SDKs:** package, environment file, `ldd`, models for your architecture.
- **Optical Flow:** the driver's `libnvidia-opticalflow.so.1` on the system, the headers, and the FRUC libraries when packaged. No models.
- **TensorRT:** `libnvinfer.so`, the headers and the pkg-config file. No models.

To check by hand, see [docs/usage.md](docs/usage.md#check-the-installation), [docs/optical-flow.md](docs/optical-flow.md#check-the-installation) and [docs/tensorrt.md](docs/tensorrt.md#check-the-installation).

## Troubleshooting

| What you see | What it means and what to do |
|---|---|
| `HTTP 402`, or an effect is skipped | Your key works, but your account has no access to that one model (for example the Early Access effect `speaker_focus`). The script skips it and goes on. Request access on the model's NGC page, or leave the effect out. `--features-afx all` already leaves it out. See [HTTP 402](docs/download.md#http-402-the-key-works-the-account-has-no-access) |
| `403`, `could not be found`, or `check-ngc.sh` prints `FAIL` | Run `scripts/check-ngc.sh`. It tells a missing key, an expired key, missing Maxine access and a missing entitlement apart. Most often you skipped **Get Access** or ran `ngc config set` with the wrong organisation. See [Troubleshooting](docs/download.md#troubleshooting) |
| `ngc` not found | The NGC tool is not installed, or `~/.local/bin` is not on your `PATH`. See [step 3 of the NGC setup](docs/download.md#3-install-the-ngc-cli) |
| The script cannot find your download | It prints the manual steps and waits. Save or download the file, then press Enter to check again, or give its place with `--src-vfx PATH` (or `--src-ar`, `--src-afx`, `--src-of`, `--src-trt`). For TensorRT it does not wait: `makepkg` downloads the file instead |
| TensorRT: `this is the ARM (aarch64) build` or `is not the archive this recipe packages` | You have the wrong file: the ARM build, or a `cuda-12.9` build instead of `cuda-13.4`. Download `TensorRT-Enterprise-11.4.0.106-Linux-x86_64-cuda-13.4-Release-external.tar.zst`. See [docs/tensorrt.md](docs/tensorrt.md#download) |
| TensorRT: `makepkg would stop on it instead of downloading`, or `selection.conf is not valid` | A source is named but missing (a stale `selection.conf`, or `--src-trt` or `NVIDIA_TRT_SRC` pointing at nothing), or the `selection.conf` is not valid. The script stops for TensorRT and deletes nothing. Fix the path, or remove `selection.conf`, so that `makepkg` downloads the archive |
| `WARNING` about disk space, `base-devel`, `fakeroot` or `bsdtar` | Free the space, or run the `sudo pacman -S --needed ...` command in the warning |
| `WARNING` that the GPU or driver is too old | The SDKs need Turing (`sm_75`) or newer and driver 570.26 or newer. Update the driver, or this GPU cannot run them |
| `pacman -U` stops on files that "exist in filesystem" | You copied Audio Effects effects in by hand earlier. The script prints the `sudo rm -r` command that clears them and asks first. See [Step 5: install](#step-5-install) |
| `pacman -U` stops on `cuda` (TensorRT) | The installed CUDA is outside 13.4 to 14. See [docs/tensorrt.md](docs/tensorrt.md#versions-and-cuda) |

For problems after the install, see the troubleshooting tables in [docs/usage.md](docs/usage.md#troubleshooting), [docs/optical-flow.md](docs/optical-flow.md#troubleshooting) and [docs/tensorrt.md](docs/tensorrt.md#troubleshooting).

## Uninstall

The script prints the removal commands in section `== 8. Undo` and never runs them. Run the `sudo pacman -R` command it printed. For one package:

```bash
sudo pacman -R maxine-vfx-sdk-local
sudo pacman -R maxine-ar-sdk-local
sudo pacman -R maxine-afx-sdk-local
sudo pacman -R nvidia-optical-flow-sdk-local
sudo pacman -R nvidia-tensorrt-sdk-local
```

If you added Audio Effects effects by hand after the install ([Step 6](#step-6-features-added-after-the-install-audio-effects)), `pacman` does not own them. Run the `sudo rm -r` of those feature directories first. The undo section names them.

## How the guided script works

The script knows five SDKs and one placeholder:

- The Maxine Video Effects, AR and Audio Effects SDKs, downloaded from NGC.
- The Optical Flow SDK and TensorRT, each one file. You download the Optical Flow SDK in a browser. For TensorRT, the script uses the file in `~/Downloads` if there is one. If there is none, `makepkg` downloads it from NVIDIA when the build runs.
- A Maxine Early Access entry that is not installable yet.

The script is a convenience over the per-package steps in [docs/download.md](docs/download.md) and the package READMEs. It does not replace them. It prints every step first as a command you could type yourself.

It has no per-SDK code: each SDK is a descriptor in `scripts/setup.d/`, and `--sdk LIST` picks from them. A dry run takes the default selection of optional features and runs no `sudo`.

### Step 1: preflight

Read-only. The script reports what it finds and explains how to fix what is missing. It fixes nothing itself.

- Arch Linux and `pacman`. Without `pacman` or without `makepkg` the script stops.
- `base-devel` (the group that holds `makepkg` and the build tools), `fakeroot` and `bsdtar` (warnings, with the `pacman -S --needed` command to install them).
- The GPU, driver and compute capability from `nvidia-smi`, the resulting `sm_<N>` architecture, a warning for a GPU older than Turing (`sm_75`) or a driver older than 570.26. `nvidia-smi` is queried once, which wakes a sleeping discrete GPU.
- Free disk space for the download directory (at least 3 GiB) and for the build directory (13.2 GiB for one SDK: the assembled tree of about 4.4 GiB, `makepkg`'s copy of it and the package). Both figures are sized for the Video Effects SDK; the TensorRT package is several GiB as well, and the Optical Flow SDK is much smaller.
- Whether the NGC CLI (the `ngc` command line tool) is on `PATH`. Only `download.sh` needs it, so only the NGC SDKs.

### Step 2: your download

For each SDK you chose, the script finds the download directory and validates it offline. It runs the package's `configure.sh --src DIR`, which reads the directory without network access, and checks every `.trtpkg.md5` checksum file against the model beside it. A download that `configure.sh` accepts and whose checksums match is valid.

Before the download is checked, you choose the SDK's optional features. The script shows a numbered list of every optional feature of the SDK, with the default selection marked `[x]` and the features that need NVIDIA's approval marked `[access required: Maxine Early Access]`, followed by the page where to request it. The list is read from the package's `download.sh`, so it is the list of `download.sh --features`. Answer with numbers or names, `all`, or Enter for the default. The features are fetched together with the SDK, before the build, so the package contains them and pacman owns them.

If the download is valid but lacks a selected feature, the script prints the `download.sh --features` command for the missing ones. If there is no usable download, it prints the manual steps and waits (for TensorRT it does not wait; see below). These steps are yours:

1. Create or log in to your NVIDIA Developer Program account (a plain NGC account is not enough).
2. Open the SDK's catalogue page, log in, select Get Access under NVIDIA Developer Program and accept NVIDIA's licence.
3. Generate a personal API key that includes the NGC Catalog service.
4. Install the NGC CLI.
5. Run `ngc config set` yourself and paste the key there.

The details of each step are in [docs/download.md](docs/download.md#prerequisites). The script then offers to run `download.sh` for you (only if `ngc` is on `PATH`, and only after a y/N; `download.sh` shows the sizes and asks again before it downloads). Whether you let it or ran the command yourself, press Enter to re-check the directory, or `s` to skip the SDK. The loop repeats until the download is valid or you skip.

**The Optical Flow SDK and TensorRT** are one file each, so there is no NGC step, no `download.sh` and no optional feature. A missing Optical Flow download prints these steps, naming the SDK's licence, and never mentions NGC:

1. Join the NVIDIA Developer Program, or log in to your account.
2. Open the SDK's download page (`https://developer.nvidia.com/opticalflow/download` or `https://developer.nvidia.com/tensorrt/download`).
3. Read the licence (the NVIDIA DesignWorks SDK License, or the NVIDIA TensorRT Software License Agreement) and select "Accept & Download" for the file the script names: `optical_flow_sdk_5.0.7.zip`, or `TensorRT-Enterprise-11.4.0.106-Linux-x86_64-cuda-13.4-Release-external.tar.zst`.
4. Save it in `~/Downloads` (where the script looks), or give its location with `--src-of PATH` or `--src-trt PATH`: the file, the directory holding it or its extracted tree.

Then press Enter to re-check, or `s` to skip the SDK. The script validates the download with the package's `configure.sh --src`, which reads the zip or archive without extracting it and checks its version. Later `configure.sh --write` records the choice, with the SHA-256 of a zip or archive. The by-hand steps are in [docs/optical-flow.md](docs/optical-flow.md#download) and [docs/tensorrt.md](docs/tensorrt.md#download). The script then runs `makepkg` with the file it has checked, passed in `NVIDIA_TRT_SRC`, so the TensorRT build downloads nothing. The Optical Flow recipe was written against NVIDIA's documented layout of the SDK, not a real archive: if your zip differs, `configure.sh` stops with an error that names what it did not find.

**TensorRT without a file** does not stop at a missing download. The script prints that `makepkg` will download `TensorRT-Enterprise-11.4.0.106-Linux-x86_64-cuda-13.4-Release-external.tar.zst` from NVIDIA when it builds and checks it against the SHA-256 the recipe pins. It names NVIDIA's TensorRT Software License Agreement: read it before you build, because by building you accept it. It gives the by-hand route for a copy you download yourself, in [docs/tensorrt.md](docs/tensorrt.md#download). It writes no `selection.conf` (step 3 prints `Selection: none`) and runs `makepkg` without `NVIDIA_TRT_SRC`. A source that is named but missing, or a `selection.conf` that is not valid, stops TensorRT with a message and deletes nothing. Fix the source, or remove `selection.conf`, so that `makepkg` downloads the file.

An SDK tree you extracted yourself (see [Alternative: an existing SDK tree](docs/download.md#alternative-an-existing-sdk-tree)) is packaged as it is. `download.sh` cannot add features to it, so the script prints the commands to fetch a download directory of its own and to select that instead.

### Step 3: selection

If the SDK has no `selection.conf`, the script prints the `configure.sh --src DIR --archs sm_<N> --features all --write` command with your detected architecture and asks before writing it. `--features all` means that everything in your download is packaged, so the selection of features happened at download time. If a `selection.conf` exists it is shown and kept unless you agree to replace it. For TensorRT with no file found, it prints `Selection: none` and writes nothing: `makepkg` downloads the file and the build needs no `selection.conf`.

### Step 4: build

`makepkg -f` runs in the package directory (with `PKGEXT=.pkg.tar`) after a y/N, because it takes several GiB and a while. An already built package is reused only when it is current. It is rebuilt when this run changed the download or the selection, when `selection.conf` is newer than the package, or when the download holds files newer than the package.

### Step 5: install

The script prints `sudo pacman -U <package>` and runs it only after a y/N. It never runs `makepkg -i` or `makepkg -s`. If the SDK is already installed at the version the recipe builds, the download, build and install are skipped.

If you added Audio Effects effects by hand earlier (step 6) and the new package now contains them, `pacman -U` would stop with "exists in filesystem" because no package owns those directories. The script detects this, prints `sudo rm -r` of exactly those directories, and runs it only after a y/N, before the install. If you decline, it does not install and prints both commands for you to run.

### Step 6: features added after the install (Audio Effects)

Audio Effects effects you did not fetch before the build can be added after the install with NVIDIA's own `download_features.sh`, which the package installs under `/opt/nvidia/maxine/afx/features`. The script compares your selection with what is packaged and what is already there, and handles only the effects that are in neither:

1. It asks before downloading, then takes the NGC API key (see [The key](#the-key)).
2. It runs `download_features.sh` from the installed `features/` directory, once per feature, into a new directory below `~/Downloads/maxine/afx-features` that exists for this run only. One run per feature means that an answer of HTTP 402 for one feature skips only that feature: the script says that your key works but the account has no access to that model, names the model's NGC page, and carries on with the others. A skipped feature is not a failed setup.
3. It checks the checksums of the download.
4. It prints `sudo cp -R --no-preserve=ownership` of only the requested feature directories into the installed `features/` directory and runs it after a y/N. `--no-preserve=ownership` makes the copy owned by root. The temporary download directory is removed after a successful copy.

Caveats of this route:

- The copied files are outside pacman's ownership. `pacman -R` does not remove them, and a later package that contains them needs the `sudo rm -r` of step 5. The undo commands at the end of the run name them.
- An effect whose feature is in the package, but at another sample rate, is not added this way, because its directory belongs to the package. The script prints the `download.sh --features` command and the rebuild instead.
- Effects that need access (speaker focus) are skipped when your account has none: see [Effects that need access](#effects-that-need-access).
- To have an effect packaged instead, fetch it with `download.sh --features` before the build.

### Step 7: check

Read-only. See [Check that it works](#check-that-it-works).

### Step 8: undo

Printed, never run: the `sudo rm -r` of the copied feature directories (first, because pacman does not own them) and `sudo pacman -R` of the installed packages.

### Effects that need access

Of the Audio Effects SDK's effects, `speaker_focus` (16k and 48k) is part of NVIDIA Maxine Early Access: NGC lists it as "available by request only", and an account without that approval is not entitled to download it. The other effects are generally available. Request access at <https://catalog.ngc.nvidia.com/orgs/nvidia/teams/maxine/models/afx_speaker_focus>. The status of every Audio Effects model is in [docs/download.md](docs/download.md#afx-sdk-model-status).

- `setup.sh` labels such effects `[access required: Maxine Early Access]` in its list, with that page.
- `--features-afx all` leaves them out, so `all` works for an account without access.
- Naming or numbering one still selects it, with a note that NGC answers HTTP 402 without approval.
- When NGC answers HTTP 402, the key is valid but the account is not entitled to the model. The download of that effect is skipped, with a message that names the model's NGC page, and the setup goes on with the rest. That holds before the build (`maxine-afx/download.sh` skips the effect and still exits 0 when other effects were fetched; see [docs/download.md](docs/download.md#http-402-the-key-works-the-account-has-no-access)) and after the install (step 6).
- `scripts/check-ngc.sh` tells you beforehand whether your account has the access: see [docs/download.md](docs/download.md#check-your-ngc-credentials).

### The key

The only step that handles a key is the optional Audio Effects post-install step. `download.sh` and `configure.sh` never do.

- The script takes `NGC_API_KEY` from the environment when it is set. Otherwise it asks for it with no echo after you agree to the download, and an empty answer skips the step.
- The key is held in a shell variable that is not exported. The script never prints, logs or stores it and never puts it on a command line. It hands it only to `download_features.sh`, in that one process's environment.
- The step refuses to run under `bash -x`, which would print the key.
- Each `download_features.sh` run gets a private `TMPDIR` (mode 700) that is removed afterwards, also after an error or an interrupt. NVIDIA's script writes the NGC token it obtains to a file in `TMPDIR` and never deletes it, so a private directory leaves nothing behind. Its fixed paths `/tmp/temp_list` and `/tmp/temp_lib.tar.gz` (file lists and libraries, no key) cannot be redirected.
- NVIDIA's `download_features.sh` itself passes the key to `curl` or `wget` on their command line, so it is visible in the process list while that script runs. This script cannot prevent that.

If this matters to you, fetch the effects with `download.sh --features` before the build instead: that route needs only your configured NGC CLI.

To check a key before you use it, `scripts/check-ngc.sh --key` reads one at a prompt without echo and checks it against NGC, without printing, logging or storing it. See [Check your NGC credentials](#check-your-ngc-credentials).

### Commands that use `sudo`

The script runs `sudo` for these commands only, each shown first, each confirmed with a y/N whose default is No, and none in a dry run:

| Command | Purpose |
|---|---|
| `sudo pacman -U <package>` | Install a package you built |
| `sudo rm -r <feature directories>` | Remove hand-copied Audio Effects feature directories that a new package contains, so that `pacman -U` can install it |
| `sudo cp -R --no-preserve=ownership <feature directories> <installed features directory>` | Copy Audio Effects effects added after the install |

It never runs `pacman -R`, `makepkg -i` or `makepkg -s`. Besides `sudo`, it runs `download.sh`, `configure.sh --write` and `makepkg -f` only after a y/N, and it queries `nvidia-smi` once.

### The Maxine Early Access entry

`--sdk maxineea` is a placeholder for the Maxine Early Access collection on NGC, which is private and available by request only. It is listed as "access required". Choosing it (with `--sdk maxineea`, or by answering yes to its question) only prints how to request access, with the collection's page and the licence it is under. It is never downloaded, configured, built, installed or verified, it needs no package directory, and `--sdk all` skips it with one line. It becomes installable once a maintainer adds the item names (visible only after access is granted) and a package directory.

### Adding an SDK to the script

Add a descriptor in `scripts/setup.d/` and the package directory it names. The format is in [scripts/setup.d/README](scripts/setup.d/README). In short, a descriptor sets:

- **How the download is obtained.** `obtain=ngc` (the default) uses the package's `download.sh` and your own NGC CLI. `obtain=browser` is for one file that you download in a browser after accepting a licence: the descriptor names the file (`download_file`, with `{version}` for the PKGBUILD's version) and the licence, and the script prints the browser steps. `obtain=auto` is for one file that the recipe's `makepkg` downloads itself (a `source=` entry). The script uses a copy at the source when there is one; otherwise it says that `makepkg` will download the file, names the licence and gives the by-hand route. TensorRT uses it.
- **What `configure.sh` takes.** `configure_select` says whether `--archs`, `--features`, both or neither is passed, so that an SDK without GPU architectures needs no detected GPU.
- **What the check looks at.** Optionally a core library for `ldd`, optional libraries, libraries that must be on the system, files that must exist, and a model directory.
- **Optional downloads and features after the install**, for an NGC SDK that has them (a catalogue read from its `download.sh`, and a script that adds features to the installed tree).
- **Placeholders.** `status=placeholder` lists an entry that is not installable yet: a request page and the steps to request access. Removing the status and adding the package keys activates it.

The contract of the package's `configure.sh` and `selection.sh` is in the same README. `scripts/tests/setup-test.sh` tests the script with stubbed tools and runs from `scripts/test.sh`.
