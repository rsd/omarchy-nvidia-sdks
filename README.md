# omarchy-nvidia-sdks

Local Arch Linux packages and a guided setup for the NVIDIA SDKs (software development kits: the libraries, headers and AI models a program uses) behind NVIDIA Broadcast-style RTX effects. You download each SDK yourself, or let `makepkg` fetch TensorRT, and this repository builds it into a package for your own machine.

## What this is for

**Why it exists.** NVIDIA Broadcast offers RTX effects for a webcam and a microphone: background blur, removal and replacement, video noise removal, eye contact, and microphone noise and room echo removal. (RTX is NVIDIA's GPU line with AI hardware, the Tensor cores.) NVIDIA ships no Broadcast application for Linux, but it does publish the SDKs behind these effects, and they are awkward to install and share on a Linux system. This repository turns them into local Arch Linux packages.

Through the SDKs you can reach:

- **Maxine Video Effects** (Maxine is NVIDIA's family of AI video and audio effects): AI green screen, background blur, video noise removal, relighting and video super resolution.
- **Maxine AR**: eye contact and face detection.
- **Maxine Audio Effects**: noise removal, room echo removal and Studio Voice.

The NVIDIA Optical Flow SDK and TensorRT (NVIDIA's library for running AI models fast on its GPUs) are packaged too.

It was made for [omarchy-broadcast](https://github.com/rsd/omarchy-broadcast), a virtual camera and microphone daemon for Omarchy that uses these SDKs on RTX GPUs. The packages do not depend on it.

**Independent and reusable.** Any project on Arch Linux or an Arch-based distribution that needs the Maxine, Optical Flow or TensorRT headers and libraries can depend on these packages instead of carrying its own copy of an SDK. The packages are `maxine-vfx-sdk-local`, `maxine-ar-sdk-local`, `maxine-afx-sdk-local`, `nvidia-optical-flow-sdk-local` and `nvidia-tensorrt-sdk-local`. Each installs under `/opt/nvidia/` (for example `/opt/nvidia/maxine/videofx` and `/opt/nvidia/tensorrt`) with an environment file that a program loads. None sets anything globally, so you can install them together. [docs/usage.md](docs/usage.md) explains how a program finds the headers, libraries and models.

**What it is not.** It is not an NVIDIA product, and NVIDIA does not support it. It does not redistribute anything from NVIDIA. You get each SDK from NVIDIA under NVIDIA's licence, with your own account where NVIDIA asks for one. TensorRT needs no account: `makepkg` can download it from NVIDIA's public server. This repository holds only the build recipes (PKGBUILDs, scripts, documentation and the source of a small compatibility shim). The effects need an NVIDIA RTX GPU (Tensor cores, Turing or newer: see [docs/gpu-support.md](docs/gpu-support.md)). The licence terms, and what you may and may not do with a built package, are in [Licences and caveats](#licences-and-caveats) at the end of this page. Read them before you use anything here.

## Quick start

This is the shortest path from nothing to an installed package. Every command runs from the root of this repository.

### Before you start

You need all of these:

- **An NVIDIA RTX GPU**, Turing (RTX 20 series) or newer.
- **Arch Linux or an Arch-based distribution** (for example Omarchy). It must have `pacman` (the package manager), `makepkg` (the tool that builds a package from a `PKGBUILD` recipe) and `fakeroot` and `bsdtar` (helper tools `makepkg` uses). `sudo pacman -S --needed base-devel fakeroot libarchive` installs them.
- **The NVIDIA driver**, version 570.26 or newer, so that `nvidia-smi` works. Check with `nvidia-smi`.
- **Free disk space**: about 3 GiB for a download and about 13 GiB for one build. A GiB is about a billion bytes.
- **A free NVIDIA Developer Program account.** You log in with it to download the Maxine and Optical Flow SDKs. TensorRT needs no login.
- **For the three Maxine SDKs only:** the NGC command line tool and a personal API key. NGC is NVIDIA's online catalogue (NVIDIA GPU Cloud) where it publishes the Maxine SDKs, and the API key is the password the tool uses. Step 3 explains how to get both. The Optical Flow SDK and TensorRT need no NGC. The Optical Flow SDK is one file that you download in a browser. TensorRT is one file that `scripts/setup.sh` or `makepkg` downloads for you from NVIDIA, or that you download in a browser.

### Who does what

| Step | You (the human) | An AI agent |
|---|---|---|
| Log in to NVIDIA, accept the licence, download a file in a browser | Yes | No |
| Create the NGC API key and enter it with `ngc config set` | Yes | No. Never paste a key into a chat or give it to an agent |
| Answer `y` to a `sudo` command | Yes | No |
| Run `scripts/setup.sh --dry-run`, `scripts/check-ngc.sh` and the checks | Optional | Yes |
| Run `scripts/setup.sh` for real | Optional | Yes, up to each question that needs you |

The script reads a key only from the `NGC_API_KEY` environment variable or from a hidden prompt, and it never prints, logs or stores it.

### Steps

1. **Get this repository.**

   ```bash
   git clone https://github.com/rsd/omarchy-nvidia-sdks.git
   cd omarchy-nvidia-sdks
   ```

2. **Look first.** A dry run checks your machine and prints every command it would run. It changes nothing and asks nothing.

   ```bash
   scripts/setup.sh --dry-run
   ```

   *Success:* the output ends with `Dry run: nothing was asked, run or written.` Lines that contain `WARNING` name something missing and how to fix it (for example a missing `base-devel`). Fix those, then run it again.

3. **Download the SDK you want. This step is yours.** Pick the SDK or SDKs first:

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

     [docs/download.md](docs/download.md#prerequisites) has the exact links and commands. The download itself (`download.sh`) runs later, inside step 4.
   - **Optical Flow (`of`):** open the download page in a browser, log in, accept the licence and save `optical_flow_sdk_5.0.7.zip` in `~/Downloads`. See [docs/optical-flow.md](docs/optical-flow.md#download).
   - **TensorRT (`trt`):** nothing to do if you have no copy. When `scripts/setup.sh` finds none in `~/Downloads`, `makepkg` downloads it from NVIDIA with no login, during the build. Read NVIDIA's TensorRT licence first: the script names it, and by building you accept it. To use your own copy instead, download `TensorRT-Enterprise-11.4.0.106-Linux-x86_64-cuda-13.4-Release-external.tar.zst` in a browser and save it in `~/Downloads`. Take the Linux x86_64 build, not ARM. See [docs/tensorrt.md](docs/tensorrt.md#download).

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

   *Success:* the `== 7. Check` section shows `ok` in every column for your SDK and the script exits with status 0. Section `== 8. Undo` then prints the commands that remove what it installed.

6. **Use it.** A program loads the package's environment file and, for Maxine, preloads a small shim. [docs/usage.md](docs/usage.md) shows how, and `docs/usage.md#check-the-installation` has the checks by hand.

To undo: run the `sudo pacman -R` command that section 8 printed. The script never runs it for you.

### If something fails

| What you see | What it means and what to do |
|---|---|
| `HTTP 402`, or an effect is skipped | Your key works, but your account has no access to that one model (for example the Early Access effect `speaker_focus`). The script skips it and goes on. Request access on the model's NGC page, or leave the effect out. `--features-afx all` already leaves it out. See [HTTP 402](docs/download.md#http-402-the-key-works-the-account-has-no-access) |
| `403`, `could not be found`, or `check-ngc.sh` prints `FAIL` | Run `scripts/check-ngc.sh`. It tells a missing key, an expired key, missing Maxine access and a missing entitlement apart. Most often you skipped **Get Access** or ran `ngc config set` with the wrong organisation. See [Troubleshooting](docs/download.md#troubleshooting) |
| `ngc` not found | The NGC tool is not installed, or `~/.local/bin` is not on your `PATH`. See [step 3 of the NGC setup](docs/download.md#3-install-the-ngc-cli) |
| The script cannot find your download | It prints the manual steps and waits. Save or download the file, then press Enter to check again, or give its place with `--src-vfx PATH` (or `--src-ar`, `--src-afx`, `--src-of`, `--src-trt`). For TensorRT it does not wait: `makepkg` downloads the file instead |
| TensorRT: `this is the ARM (aarch64) build` or `is not the archive this recipe packages` | You have the wrong file: the ARM build, or a `cuda-12.9` build instead of `cuda-13.4`. Download `TensorRT-Enterprise-11.4.0.106-Linux-x86_64-cuda-13.4-Release-external.tar.zst`. See [docs/tensorrt.md](docs/tensorrt.md#download) |
| `WARNING` about disk space, `base-devel`, `fakeroot` or `bsdtar` | Free the space, or run the `sudo pacman -S --needed ...` command in the warning |
| `WARNING` that the GPU or driver is too old | The SDKs need Turing (`sm_75`) or newer and driver 570.26 or newer. Update the driver, or this GPU cannot run them |
| `pacman -U` stops on files that "exist in filesystem" | You copied Audio Effects effects in by hand earlier. The script prints the `sudo rm -r` command that clears them and asks first. See [setup.md](docs/setup.md#5-install) |

### Options of `scripts/setup.sh`

| Option | Effect |
|---|---|
| `--sdk LIST` | The SDKs to set up, comma separated: `vfx`, `ar`, `afx`, `of`, `trt`, `maxineea`, or `all`. Without it the script asks about each one. `maxineea` is a placeholder that only prints how to request Early Access; `all` skips it |
| `--features-KEY LIST` | The optional downloads of one SDK (`--features-vfx`, `--features-ar`, `--features-afx`): names, their numbers in the list, or `all`, comma separated. `all` leaves out the effects marked "access required", which you name or number to choose them. Without the option the script shows the list and asks; a dry run takes the default. `scripts/setup.sh --help` prints every SDK's feature list |
| `--src-KEY PATH` | Where the download of one SDK is (`--src-vfx`, `--src-trt` and so on): its download directory, or for an SDK downloaded as one file, that file, the directory holding it or its extracted tree |
| `--dry-run` | Read-only: check, detect and print the commands, ask nothing, change nothing. `--print-commands` is an alias |
| `-h`, `--help` | The options, where each SDK comes from and the feature lists |

Examples:

```bash
scripts/setup.sh --dry-run                                        # look first
scripts/setup.sh --sdk afx --features-afx all                     # Audio Effects, every effect you have access to
scripts/setup.sh --sdk trt                                        # TensorRT only
scripts/setup.sh --sdk afx --features-afx superres-16k_to_48k     # one named effect
scripts/setup.sh --sdk vfx,afx --dry-run                          # look at two SDKs
```

The script runs the whole procedure for any of the five SDKs: checks of your machine, detection of your download, the optional features of a Maxine SDK, `configure.sh` (which saves your choice of features and GPU), `makepkg`, the installation, a check of the result and the commands to undo it. Login, licence acceptance and `ngc config set` stay with you, and so does the browser download of the Optical Flow SDK. For TensorRT, the script uses the file in `~/Downloads` when there is one, and otherwise `makepkg` downloads it from NVIDIA during the build (see [docs/tensorrt.md](docs/tensorrt.md#download)). The steps, the options and what the script does with `sudo` are in [docs/setup.md](docs/setup.md).

Some effects need an approval that NGC grants on request (Maxine Early Access). `setup.sh` marks them "access required" in its lists and prints the page where to ask. If your account has no access, NGC answers HTTP 402 and that effect is skipped; the rest of the run goes on. See [HTTP 402: the key works, the account has no access](docs/download.md#http-402-the-key-works-the-account-has-no-access).

### Check your NGC credentials

Before a large download, `scripts/check-ngc.sh` tells you whether NGC accepts your key and what your account may download. It is read-only, and it never prints, logs or stores a key or a token:

```bash
scripts/check-ngc.sh                 # the NGC CLI's key, Maxine access, the Early Access models
scripts/check-ngc.sh --key --no-cli  # only a key you type at the prompt
```

It prints one line per check (OK, FAIL or SKIP) and a hint after each FAIL. It exits 0 when every check passed, 1 when one failed and 2 for a usage error. Type a key at the prompt of `--key`, which does not echo it. Do not put the key on the command line as `NGC_API_KEY=... scripts/check-ngc.sh`: it stays in your shell history. What is checked, what each result means and the options are in [docs/download.md](docs/download.md#check-your-ngc-credentials).

### Manual steps for one SDK

The same procedure by hand, one command per step. This example is the Video Effects SDK.

1. Download the SDK files from NGC with one command:

   ```bash
   maxine-vfx/download.sh
   ```

   The script detects your GPU architecture, asks NGC what exists, prints a table of what it would download and how big it is, and asks for confirmation. It downloads only what is missing, verifies the result and retries failures. Use `--dry-run` to look without downloading, `--preset all` for every feature, and `--yes` to skip the question. The options are in [docs/download.md](docs/download.md#download-with-one-command). The result is one directory, by default `~/Downloads/maxine`.

2. Choose your features and architectures, and build the package. The download script prints these commands with your paths filled in, and `--build` runs them for you:

   ```bash
   maxine-vfx/configure.sh --src ~/Downloads/maxine --archs sm_120 --features all --write
   cd maxine-vfx && makepkg -f
   ```

   `configure.sh` saves the choice in `maxine-vfx/selection.conf` (see [Choose your features and GPU](#choose-your-features-and-gpu)), and `makepkg` reads it. Replace `sm_120` with your GPU's architecture (the number from `nvidia-smi --query-gpu=compute_cap --format=csv,noheader`, without the dot, after `sm_`; see [docs/gpu-support.md](docs/gpu-support.md)). Without `selection.conf` you can pass the same choice in the environment: `MAXINE_VFX_SRC=~/Downloads/maxine MAXINE_VFX_ARCHS=sm_120 MAXINE_VFX_FEATURES=all makepkg -f`.

3. Install the package yourself (run it in `maxine-vfx/`, where `makepkg` left it):

   ```bash
   sudo pacman -U maxine-vfx-sdk-local-*.pkg.tar*
   ```

   Only `scripts/setup.sh` runs `sudo` or installs anything, and it shows each command and asks before running it. `download.sh`, `configure.sh` and the PKGBUILDs never do.
4. Use it from your programs, following [docs/usage.md](docs/usage.md).

The build options (`MAXINE_VFX_SRC`, `MAXINE_VFX_ARCHS`, `MAXINE_VFX_FEATURES`) are described in [maxine-vfx/README.md](maxine-vfx/README.md). If you prefer to type the `ngc` commands yourself, [docs/download.md](docs/download.md#download-by-hand) lists them in full.

## What is included

| Directory | Package | Contents |
|---|---|---|
| [`maxine-vfx/`](maxine-vfx/) | `maxine-vfx-sdk-local` | NVIDIA Maxine Video Effects SDK 1.3.0.0: the features and GPU architectures you download and select. The download helper fetches AI green screen, background blur and video noise removal by default |
| [`maxine-ar/`](maxine-ar/) | `maxine-ar-sdk-local` | NVIDIA Maxine AR SDK 1.2.0.0: eye contact (gaze redirection), face box detection, facial landmarks, face expressions and the other documented AR features. The download helper fetches eye contact with the two features it depends on by default |
| [`maxine-afx/`](maxine-afx/) | `maxine-afx-sdk-local` | NVIDIA Maxine Audio Effects SDK 3.0.0 (package version 3.0.0.12): noise removal, room echo removal, both together and Studio Voice, at the sample rates you download. The download helper fetches those four at 48 kHz by default |
| [`nvidia-optical-flow/`](nvidia-optical-flow/) | `nvidia-optical-flow-sdk-local` | NVIDIA Optical Flow SDK 5.0.7 from your own `optical_flow_sdk_5.0.7.zip`: the headers, the FRUC (frame rate up-conversion) library when your download has it, and the samples and NvOFTracker as source, under `/opt/nvidia/optical-flow`. The runtime library comes from the NVIDIA driver. Guide: [docs/optical-flow.md](docs/optical-flow.md) |
| [`nvidia-tensorrt/`](nvidia-tensorrt/) | `nvidia-tensorrt-sdk-local` | NVIDIA TensorRT 11.4.0.106 for Linux x86_64 and CUDA 13.4, from the archive that `makepkg` downloads from NVIDIA or that you supply (the ARM build is refused), installed as shipped under `/opt/nvidia/tensorrt`, with a pkg-config file and an environment file. It sits beside the AUR's `tensorrt`, which installs into `/usr`, and it provides `tensorrt` too: a package that depends on `tensorrt` finds TensorRT through the environment file or pkg-config, not under `/usr`. Guide: [docs/tensorrt.md](docs/tensorrt.md) |

The three Maxine packages follow the same pattern. You download the SDK from NGC, you choose the features and GPU architectures, and `makepkg` builds one package from your download. Each installs under its own `/opt/nvidia/maxine/` directory with its own environment file, and none sets anything globally, so you can install them together.

The Optical Flow SDK and TensorRT packages are simpler. Each is one file, obtained after you accept NVIDIA's licence, and there are no features or architectures to choose. You download the Optical Flow file in a browser. For TensorRT, `makepkg` can download the file from NVIDIA, or you can download it in a browser. They install under `/opt/nvidia/optical-flow` and `/opt/nvidia/tensorrt`, with their own environment files, and you can install them beside the others.

`scripts/setup.sh` also lists a Maxine Early Access entry. It is a placeholder that only prints how to request access.

The sections up to [Not limited to one GPU or to today's features](#not-limited-to-one-gpu-or-to-todays-features) describe the Video Effects package. [The AR and Audio Effects packages](#the-ar-and-audio-effects-packages) follow.

## Choose your features and GPU

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

This checks the selection against what is present (a feature or architecture you have not downloaded is an error, and the message names the command that fetches it) and writes `maxine-vfx/selection.conf`. Git ignores the file because it holds a local path. The PKGBUILD reads it when it builds. It is parsed as plain `KEY=value` lines and never executed. An environment variable overrides the file, and the file overrides the built-in default. `configure.sh --show` prints the current file.

To fetch more features or architectures, run `maxine-vfx/download.sh` again with `--features` or `--archs`, then `configure.sh` and `makepkg` again. Which GPUs are supported, how to find your architecture and how to fetch models for another GPU are in [docs/gpu-support.md](docs/gpu-support.md).

### Not limited to one GPU or to today's features

- **Features.** `MAXINE_VFX_FEATURES` is `all` (the default: every feature found in your download is packaged) or a list such as `nvvfxgreenscreen,nvvfxbackgroundblur`: exactly those are packaged, and each must be present. To add a feature, download its library and models into the same directory (`download.sh --features ...`, or your own `ngc`), then rebuild. The steps are in [docs/download.md](docs/download.md#more-features).
- **GPU architectures.** `MAXINE_VFX_ARCHS` takes a list (`"sm_120 sm_89"`) or `all`. The SDK needs a Tensor-core GPU, Turing or newer; see [docs/gpu-support.md](docs/gpu-support.md). Each architecture adds the model packages of every feature that has models: for `sm_120` that is about 113 MiB for green screen, 3.7 MiB for denoising and 79 MiB for relighting. The sizes per architecture are in [docs/gpu-support.md](docs/gpu-support.md#size-cost-per-architecture).
- **Sizes** in these documents are stated in MiB or GiB (2^20 and 2^30 bytes), or in GB (10^9 bytes), explicitly. The default download for `sm_120` is about 2.75 GiB, of which the SDK core is 2.63 GiB. The assembled SDK tree is 4.4 GiB (4,671,229,191 bytes) and the built package (`PKGEXT=.pkg.tar`) is about 4.4 GiB too. With all eight features and `sm_120` models the assembled tree is 5,054,183,158 bytes (4.71 GiB) and the package is about 4.7 GiB (`PKGEXT=.pkg.tar`); the five features outside the default add 326,922,413 bytes (about 312 MiB) to the download.

## The AR and Audio Effects packages

`maxine-ar/` and `maxine-afx/` have the same layout, options and steps as `maxine-vfx/`: `download.sh`, `configure.sh`, a PKGBUILD that reads `selection.conf` and the environment, and an environment file for consumers. Each package's README is the reference for its build inputs: [maxine-ar/README.md](maxine-ar/README.md) and [maxine-afx/README.md](maxine-afx/README.md). Each package has its own download directory, by default `~/Downloads/maxine/ar-sdk` and `~/Downloads/maxine/afx-sdk`, so that one source directory holds one SDK.

```bash
# AR SDK: eye contact, face box and landmark detection
maxine-ar/download.sh
maxine-ar/configure.sh --src ~/Downloads/maxine/ar-sdk --archs sm_120 --features all --write
cd maxine-ar && makepkg -f

# Audio Effects SDK: noise removal, room echo removal and Studio Voice at 48 kHz
maxine-afx/download.sh
maxine-afx/configure.sh --src ~/Downloads/maxine/afx-sdk --archs sm_120 --features all --write
cd maxine-afx && PKGEXT=.pkg.tar makepkg -f
```

Then install with `sudo pacman -U` yourself (or let `scripts/setup.sh` do these steps, after a confirmation) and use the package as described in [docs/usage.md](docs/usage.md). The build inputs are `MAXINE_AR_SRC`, `MAXINE_AR_ARCHS` and `MAXINE_AR_FEATURES`, and `MAXINE_AFX_SRC`, `MAXINE_AFX_ARCHS` and `MAXINE_AFX_FEATURES`. The Audio Effects package has no sample-rate input: every sample rate present in your download is packaged.

| Package | Features | NGC names |
|---|---|---|
| `maxine-ar-sdk-local` | Eye contact (`nvargazeredirection`), face box detection (`nvarfaceboxdetection`), facial landmarks (`nvarlandmarkdetection`), face expressions (`nvarfaceexpressions`); also offered: body detection, body pose and lip synchronisation (`nvarbodydetection`, `nvarbodyposeestimation`, `nvarlipsync`) | `nvidia/maxine/<feature>` |
| `maxine-afx-sdk-local` | Noise removal (`denoiser`), room echo removal (`dereverb`), both in one (`dereverb_denoiser`), Studio Voice (`studio_voice`); also offered: audio super resolution (`superres`), the 16 kHz variants and speaker focus (Early Access, by request only) | `nvidia/maxine/afx_<feature>` |

Eye Contact and Auto Frame in NVIDIA Broadcast belong to the AR SDK, not to the Video Effects SDK. The names, preset contents, manual `ngc` commands and sizes are in [docs/download.md](docs/download.md#maxine-ar-sdk) for the AR SDK and [docs/download.md](docs/download.md#maxine-audio-effects-sdk) for the Audio Effects SDK. The GPU architectures are in [docs/gpu-support.md](docs/gpu-support.md#ar-and-audio-effects-sdks).

## Repository layout

```
README.md
LICENSE-MIT, LICENSE-APACHE
.gitignore
.githooks/                        pre-commit, pre-merge-commit, pre-push: run the licence guard
scripts/check-no-nvidia.sh        licence guard: refuses NVIDIA files, SDK trees, NGC download directories
scripts/setup.sh                  guided setup: preflight, download detection, configure, build, install, check, undo
scripts/check-ngc.sh              read-only check of your NGC key and of your account's access to the Maxine models
scripts/setup.d/                  one descriptor per SDK for setup.sh (format in scripts/setup.d/README)
scripts/test.sh                   runs every check of this repository
scripts/tests/                    tests of the guard, of env.sh, of setup.sh, of check-ngc.sh and of a PKGBUILD fixture build
docs/setup.md                     the guided setup: steps, options, key handling, the sudo commands, undo
docs/download.md                  what is downloaded, from where and whether it needs a login, for every SDK; and downloading the Maxine SDKs from NGC: the one-command path, the manual steps, sizes, the credential check, access (HTTP 402), troubleshooting, for the three Maxine SDKs
docs/optical-flow.md              the Optical Flow SDK package: browser download, what it installs, environment file, use, check, troubleshooting
docs/tensorrt.md                  the TensorRT package: the download (automatic or in a browser), what it installs, environment file, pkg-config, CMake and RPATH, the AUR's tensorrt, CUDA versions
docs/usage.md                     how a program uses each installed package: environment file, shim, models
docs/gpu-support.md               supported GPUs, architectures and how to fetch their models
maxine-vfx/PKGBUILD               the package recipe
maxine-vfx/assemble.sh            builds the SDK tree from your download
maxine-vfx/download.sh            downloads what you need with your configured ngc: probes, shows sizes, verifies
maxine-vfx/configure.sh           shows what your download holds and saves your selection
maxine-vfx/selection.sh           parses selection.conf (never executes it), for the PKGBUILD and configure.sh
maxine-vfx/README.md              build instructions for the package
maxine-vfx/tests/                 tests of assemble.sh, configure.sh and download.sh on tiny fake files
maxine-ar/                        the AR SDK package: PKGBUILD, assemble.sh, download.sh, configure.sh, selection.sh, README.md, tests/ (same roles as in maxine-vfx/)
maxine-afx/                       the Audio Effects SDK package: the same files as maxine-ar/
nvidia-optical-flow/              the Optical Flow SDK package: PKGBUILD, assemble.sh, configure.sh, selection.sh, README.md, tests/ (no download.sh: the zip is downloaded in a browser)
nvidia-tensorrt/                  the TensorRT package: PKGBUILD, source.sh, configure.sh, selection.sh, README.md, tests/ (no download.sh: makepkg downloads the archive, or you supply it)
tools/os-release-shim/            the compatibility shim and its test
tools/maxine-probe/               a small program that checks the SDK loads
```

## Testing

```bash
scripts/test.sh
```

This runs every check in the repository, for all five packages: shellcheck over every script, the syntax and metadata of each PKGBUILD, the fixture tests of each package's `assemble.sh`, `configure.sh` and `download.sh` (the last against a fake `ngc`), the `configure.sh` and `selection.conf` tests of the Optical Flow and TensorRT packages on tiny fake zips, archives and trees, a `makepkg` build of each PKGBUILD against fake SDK files, the shim test, the tests of `scripts/setup.sh` and `scripts/check-ngc.sh` (with stubbed `pacman`, `sudo`, `makepkg`, `ngc`, `curl` and `nvidia-smi`, so nothing is installed and nothing reaches NGC), and the licence guard and its hooks, then the guard over the whole tree. It needs `shellcheck` (a tool that checks shell scripts for mistakes). A GPU is not required, it uses no network and it needs no NVIDIA download. The `makepkg` fixture builds, and the Optical Flow and TensorRT `configure.sh` tests where they need `bsdtar`, are skipped when `makepkg`, `fakeroot` or `bsdtar` is missing.

## Licences and caveats

### Licence and personal use

Read this before using anything here.

- **You accept NVIDIA's licence, and you download the SDK yourself**, with your own account where NVIDIA asks for one: from NVIDIA NGC for the Maxine SDKs, and in a browser from NVIDIA's developer site for the Optical Flow SDK. TensorRT is also served by NVIDIA without a login, and `makepkg` can download it for you under NVIDIA's TensorRT Software License Agreement, or you can download it in a browser. Apart from that download, the recipes only automate what happens after your download.
- **This repository holds only recipes**: PKGBUILDs, scripts, documentation and the source of a small compatibility shim. **Nothing from NVIDIA is committed**: no SDK files, libraries, headers, models (`*.trtpkg`), tarballs or licence PDFs. The guard `scripts/check-no-nvidia.sh` enforces this: it refuses NVIDIA's file types (libraries, models and their `*.trtpkg.*` checksum sidecars, archives, PDFs, SDK headers, including those of the Optical Flow SDK and TensorRT), an unpacked SDK tree (`VideoFX/`, `ARSDK/`, `Audio_Effects_SDK/`, `Optical_Flow_SDK_*/`, `TensorRT-*/`), an NGC download directory, an SDK's top-level names (`lib/`, `include/`, `features/`, `external/`, `share/`, `samples/`, `licenses/`, `nvafx/`, `bin/`, `docs/`, `version.h`, `Changelog.txt`) placed directly inside a recipe directory (and the matching top-level names of the Optical Flow SDK and of the TensorRT archive inside their recipe directories), and file content that carries an NVIDIA marker. Enable its hooks in your clone with:

  ```bash
  git config core.hooksPath .githooks
  ```

  The hooks are `pre-commit`, `pre-merge-commit` and `pre-push`. `pre-push` checks the commits being pushed with the guard's `--range` mode. `git commit --no-verify` bypasses them (as does `git push --no-verify` for `pre-push`), so the guard is a safety net and not an access control. `scripts/check-no-nvidia.sh --all` checks the working tree, not the history: a file committed earlier stays in the history until you rewrite it.

- **The built package contains NVIDIA software and is for your own machine only.** Never upload it to a package repository, to the AUR as a binary, to a release page, or share it in any other way. The NVIDIA Software License Agreement for the Maxine SDKs (8.5) forbids redistribution, including in "publicly accessible software repositories". The Optical Flow SDK is under the NVIDIA DesignWorks SDK License, which does not allow redistributing the SDK stand-alone, and TensorRT is under the TensorRT Software License Agreement, which allows installing and using it internally and does not allow redistributing it, except its runtime libraries inside an application that adds material functionality. The TensorRT package is not that, and it ships a short note on these terms in `/usr/share/licenses/nvidia-tensorrt-sdk-local/TERMS.txt`. Nothing built here is that: read the licence you accept for each SDK.
- **Do not publish benchmark results** (the Maxine licence, 8.9), and do not reverse engineer the software.
- **NVIDIA does not support this configuration.** Arch Linux and other distributions the SDK does not list, packages built by a third-party recipe, and client-side use of an SDK documented for servers, are outside what NVIDIA supports. Expect no vendor support.
- This is not legal advice. Read the licence you accept.

### Licence of this repository's content

MIT OR Apache-2.0, at your option: see [LICENSE-MIT](LICENSE-MIT) and [LICENSE-APACHE](LICENSE-APACHE). This covers only the content of this repository. It does not apply to any NVIDIA software you download or to a package built from it.
